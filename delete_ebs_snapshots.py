#!/usr/bin/env python3
"""
Foolproof EBS snapshot deletion tool.

Safety features:
  * Dry-run by default — must pass --apply to actually delete.
  * Refuses to delete snapshots that back a registered AMI (would orphan it).
  * Refuses to delete snapshots younger than --min-age-days (default 7).
  * Refuses to delete more than --max-delete snapshots in one run.
  * Filters by region, owner, tag, age, and explicit ID allow-list / deny-list.
  * Interactive confirmation (typed phrase) unless --yes is supplied.
  * Parallel deletion with bounded concurrency and per-call retry/backoff.
  * Structured JSON log of every action to ./snapshot-deletions-<ts>.jsonl.

Usage:
  # Preview snapshots older than 30 days (safe, default):
  ./delete_ebs_snapshots.py --region us-east-1 --older-than-days 30

  # Delete snapshots older than 30 days, filtered by tag:
  ./delete_ebs_snapshots.py --region us-east-1 \
      --tag Environment=dev --older-than-days 30 --apply --yes

  # Delete an explicit allow-list:
  ./delete_ebs_snapshots.py --region us-east-1 \
      --ids snap-aaaa,snap-bbbb --apply
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from typing import Iterable

try:
    import boto3
    from botocore.config import Config
    from botocore.exceptions import ClientError
except ImportError:
    sys.stderr.write("boto3 is required: pip install boto3\n")
    sys.exit(2)


CONFIRM_PHRASE = "DELETE SNAPSHOTS"
LOG = logging.getLogger("ebs-snapshot-cleanup")


@dataclass
class Options:
    region: str
    owner_ids: list[str]
    tag_filters: list[tuple[str, str]]
    min_age_days: int
    max_delete: int
    ids_allow: set[str]
    ids_deny: set[str]
    apply: bool
    yes: bool
    concurrency: int
    keep_ami_backing: bool = True
    log_path: str = field(default_factory=lambda: f"snapshot-deletions-{int(time.time())}.jsonl")


def parse_args(argv: list[str]) -> Options:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--region", required=True, help="AWS region")
    p.add_argument("--owner", action="append", default=[],
                   help="Snapshot owner account ID (repeatable). Defaults to 'self'.")
    p.add_argument("--tag", action="append", default=[],
                   help="Tag filter Key=Value (repeatable; AND semantics)")
    p.add_argument("--min-age-days", "--older-than-days", type=int, default=7,
                   dest="min_age_days",
                   help="Delete only snapshots older than N days (default 7)")
    p.add_argument("--max-delete", type=int, default=200,
                   help="Abort if more than this many snapshots would be deleted (default 200)")
    p.add_argument("--ids", default="",
                   help="Comma-separated allow-list of snapshot IDs (only these are eligible)")
    p.add_argument("--exclude-ids", default="",
                   help="Comma-separated deny-list of snapshot IDs (never deleted)")
    p.add_argument("--apply", action="store_true",
                   help="Actually delete. Without this flag the script is a dry-run.")
    p.add_argument("--yes", action="store_true",
                   help="Skip interactive confirmation. --apply still required.")
    p.add_argument("--concurrency", type=int, default=8,
                   help="Parallel delete workers (default 8)")
    p.add_argument("--allow-ami-backing", action="store_true",
                   help="DANGEROUS: allow deleting snapshots that back a registered AMI")
    p.add_argument("--verbose", "-v", action="store_true")
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    tag_filters: list[tuple[str, str]] = []
    for t in args.tag:
        if "=" not in t:
            p.error(f"--tag must be Key=Value, got {t!r}")
        k, v = t.split("=", 1)
        tag_filters.append((k.strip(), v.strip()))

    return Options(
        region=args.region,
        owner_ids=args.owner or ["self"],
        tag_filters=tag_filters,
        min_age_days=args.min_age_days,
        max_delete=args.max_delete,
        ids_allow={s.strip() for s in args.ids.split(",") if s.strip()},
        ids_deny={s.strip() for s in args.exclude_ids.split(",") if s.strip()},
        apply=args.apply,
        yes=args.yes,
        concurrency=max(1, min(args.concurrency, 32)),
        keep_ami_backing=not args.allow_ami_backing,
    )


def ec2_client(region: str):
    return boto3.client(
        "ec2",
        region_name=region,
        config=Config(retries={"max_attempts": 10, "mode": "adaptive"}),
    )


def list_snapshots(ec2, opts: Options) -> list[dict]:
    filters = [{"Name": f"tag:{k}", "Values": [v]} for k, v in opts.tag_filters]
    paginator = ec2.get_paginator("describe_snapshots")
    out: list[dict] = []
    for page in paginator.paginate(OwnerIds=opts.owner_ids, Filters=filters):
        out.extend(page.get("Snapshots", []))
    return out


def ami_backing_snapshot_ids(ec2) -> set[str]:
    paginator = ec2.get_paginator("describe_images")
    ids: set[str] = set()
    for page in paginator.paginate(Owners=["self"]):
        for image in page.get("Images", []):
            for bdm in image.get("BlockDeviceMappings", []):
                ebs = bdm.get("Ebs") or {}
                if ebs.get("SnapshotId"):
                    ids.add(ebs["SnapshotId"])
    return ids


def filter_eligible(snaps: Iterable[dict], opts: Options, ami_ids: set[str]) -> tuple[list[dict], list[tuple[dict, str]]]:
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=opts.min_age_days)
    eligible: list[dict] = []
    skipped: list[tuple[dict, str]] = []

    for s in snaps:
        sid = s["SnapshotId"]
        if opts.ids_allow and sid not in opts.ids_allow:
            skipped.append((s, "not in allow-list"))
            continue
        if sid in opts.ids_deny:
            skipped.append((s, "in deny-list"))
            continue
        if s.get("State") != "completed":
            skipped.append((s, f"state={s.get('State')}"))
            continue
        if s.get("StartTime") and s["StartTime"] > cutoff:
            skipped.append((s, f"younger than {opts.min_age_days}d"))
            continue
        if opts.keep_ami_backing and sid in ami_ids:
            skipped.append((s, "backs a registered AMI"))
            continue
        eligible.append(s)
    return eligible, skipped


def confirm(opts: Options, eligible: list[dict]) -> bool:
    if not opts.apply:
        return False
    if opts.yes:
        return True
    sys.stderr.write(
        f"\nAbout to DELETE {len(eligible)} snapshots in {opts.region}.\n"
        f"Type exactly  {CONFIRM_PHRASE!r}  to proceed: "
    )
    sys.stderr.flush()
    return sys.stdin.readline().strip() == CONFIRM_PHRASE


def delete_one(ec2, snap: dict) -> dict:
    sid = snap["SnapshotId"]
    try:
        ec2.delete_snapshot(SnapshotId=sid)
        return {"snapshot_id": sid, "status": "deleted", "size_gib": snap.get("VolumeSize")}
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        return {"snapshot_id": sid, "status": "error", "error_code": code, "error": str(e)}


def run(opts: Options) -> int:
    ec2 = ec2_client(opts.region)
    LOG.info("Listing snapshots in %s (owners=%s)…", opts.region, opts.owner_ids)
    snaps = list_snapshots(ec2, opts)
    LOG.info("Found %d snapshots before filtering.", len(snaps))

    ami_ids: set[str] = set()
    if opts.keep_ami_backing:
        ami_ids = ami_backing_snapshot_ids(ec2)
        LOG.info("Found %d AMI-backing snapshots to protect.", len(ami_ids))

    eligible, skipped = filter_eligible(snaps, opts, ami_ids)
    LOG.info("Eligible for deletion: %d  |  Skipped: %d", len(eligible), len(skipped))

    for s, why in skipped[:20]:
        LOG.debug("skip %s (%s)", s["SnapshotId"], why)

    if not eligible:
        LOG.info("Nothing to do.")
        return 0

    if len(eligible) > opts.max_delete:
        LOG.error(
            "Refusing to delete %d snapshots — exceeds --max-delete=%d. "
            "Narrow filters or raise the limit explicitly.",
            len(eligible), opts.max_delete,
        )
        return 3

    total_gib = sum(s.get("VolumeSize", 0) for s in eligible)
    print(f"\nPlan ({'APPLY' if opts.apply else 'DRY-RUN'}): "
          f"{len(eligible)} snapshots, ~{total_gib} GiB total\n")
    for s in eligible[:50]:
        print(f"  {s['SnapshotId']}  {s.get('VolumeSize', '?')}GiB  "
              f"{s.get('StartTime').isoformat() if s.get('StartTime') else '?'}  "
              f"{s.get('Description', '')[:60]}")
    if len(eligible) > 50:
        print(f"  … and {len(eligible) - 50} more")

    if not opts.apply:
        print("\nDry-run only. Re-run with --apply to delete.")
        return 0

    if not confirm(opts, eligible):
        LOG.error("Confirmation phrase did not match. Aborting.")
        return 4

    deleted = errors = 0
    with open(opts.log_path, "w") as log_fh:
        with concurrent.futures.ThreadPoolExecutor(max_workers=opts.concurrency) as pool:
            futures = {pool.submit(delete_one, ec2, s): s for s in eligible}
            for fut in concurrent.futures.as_completed(futures):
                rec = fut.result()
                rec["timestamp"] = dt.datetime.now(dt.timezone.utc).isoformat()
                rec["region"] = opts.region
                log_fh.write(json.dumps(rec) + "\n")
                if rec["status"] == "deleted":
                    deleted += 1
                    LOG.info("deleted %s", rec["snapshot_id"])
                else:
                    errors += 1
                    LOG.error("failed %s: %s", rec["snapshot_id"], rec.get("error_code"))

    LOG.info("Done. deleted=%d errors=%d  log=%s", deleted, errors, opts.log_path)
    return 0 if errors == 0 else 1


def main() -> int:
    try:
        return run(parse_args(sys.argv[1:]))
    except KeyboardInterrupt:
        LOG.error("Interrupted.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
