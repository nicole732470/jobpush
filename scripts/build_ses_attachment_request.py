#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
from email.message import EmailMessage
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("attachment")
    parser.add_argument("report")
    parser.add_argument("request_json")
    parser.add_argument("--sender", required=True)
    parser.add_argument("--recipients", required=True, help="Comma-separated recipient addresses")
    parser.add_argument("--date", required=True)
    args = parser.parse_args()

    attachment = Path(args.attachment)
    with open(args.report, encoding="utf-8") as handle:
        report = json.load(handle)
    message = EmailMessage()
    message["Subject"] = f"Job Push Daily Export — {args.date}"
    message["From"] = args.sender
    recipients = [value.strip() for value in args.recipients.split(",") if value.strip()]
    message["To"] = ", ".join(recipients)
    message.set_content(
        "Job Push daily export is attached.\n\n"
        f"Jobs discovered: {report['jobs_discovered']}\n"
        f"Jobs processed: {report['jobs_processed']}\n"
        f"Successful JD retrieval: {report['successful_jd_retrieval']}\n"
        f"Failed jobs: {report['failed_jobs']}\n"
        f"Exported jobs: {report['exported_jobs']}\n"
    )
    message.add_attachment(
        attachment.read_bytes(), maintype="application", subtype="json", filename=attachment.name
    )
    request = {
        "FromEmailAddress": args.sender,
        "Destination": {"ToAddresses": recipients},
        "Content": {"Raw": {"Data": base64.b64encode(message.as_bytes()).decode("ascii")}},
    }
    with open(args.request_json, "w", encoding="utf-8") as handle:
        json.dump(request, handle, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
