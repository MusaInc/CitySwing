"""Answer an App Review "Information Needed" (Guideline 2.1) request for CitySwing.

Run by .github/workflows/appstore_listing.yml when `review_reply` is set.
Env: KEY_ID, ISSUER, KEY, VERSION, ATTACHMENT (repo path of the screen
recording, optional), SUBMIT=1 to resubmit the version for review.

  * App Review notes ← store/review_notes.txt
  * replaces the App Review attachments with ATTACHMENT (upload → checksum →
    waits until Apple reports COMPLETE)
  * SUBMIT=1: resubmits the version (reuses the open review submission if
    Apple left one in UNRESOLVED_ISSUES / READY_FOR_REVIEW, else creates one)
"""
import hashlib
import os
import sys
import time
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from listing import BUNDLE, NOTES, ROOT, call, get, patch  # noqa: E402


def upload_attachment(rd_id, path):
    blob = open(path, "rb").read()
    # Apple allows ONE attachment: remove the old one first.
    for o in get(f"/v1/appStoreReviewDetails/{rd_id}/appStoreReviewAttachments")["data"]:
        call("DELETE", f"/v1/appStoreReviewAttachments/{o['id']}")
        print("ATTACHMENT removed old", o["attributes"].get("fileName"), o["attributes"].get("fileSize"))
    att = call("POST", "/v1/appStoreReviewAttachments", {"data": {"type": "appStoreReviewAttachments",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(blob)},
        "relationships": {"appStoreReviewDetail": {"data": {"type": "appStoreReviewDetails", "id": rd_id}}}}})["data"]
    for op in att["attributes"]["uploadOperations"]:
        call(op["method"], "", raw=blob[op["offset"]:op["offset"] + op["length"]], url=op["url"],
             headers={h["name"]: h["value"] for h in op["requestHeaders"]})
    patch("appStoreReviewAttachments", att["id"], {"uploaded": True,
          "sourceFileChecksum": hashlib.md5(blob).hexdigest()})
    print("ATTACHMENT uploaded", os.path.basename(path), len(blob), "bytes")
    state = None
    for _ in range(40):
        time.sleep(15)
        st = get(f"/v1/appStoreReviewAttachments/{att['id']}")["data"]["attributes"].get("assetDeliveryState") or {}
        state = st.get("state")
        print("ATTACHMENT STATE", state, st.get("errors") or "")
        if state in ("COMPLETE", "FAILED"):
            break
    if state != "COMPLETE":
        raise SystemExit("attachment not accepted by Apple: %s" % state)


def resubmit(app_id, vid):
    subs = get(f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&limit=20")["data"]
    for s in subs:
        print("SUBMISSION", s["id"], s["attributes"].get("state"), s["attributes"].get("submittedDate"))
    sub = next((s for s in subs if s["attributes"].get("state") in ("UNRESOLVED_ISSUES", "READY_FOR_REVIEW")), None)
    if sub is None:
        sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("SUBMISSION created", sub["id"])
    items = get(f"/v1/reviewSubmissions/{sub['id']}/items")["data"]
    for it in items:
        print("ITEM", it["id"], it["attributes"].get("state"))
    if not items:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("ITEM added version")
    r = patch("reviewSubmissions", sub["id"], {"submitted": True})
    print("SUBMITTED", sub["id"], r.get("data", {}).get("attributes", {}).get("state"))


def main():
    version = os.environ["VERSION"]
    app_id = get(f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    vs = get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    ver = next(v for v in vs if v["attributes"]["versionString"] == version)
    vid = ver["id"]
    print("VERSION", version, ver["attributes"].get("appStoreState"))
    try:
        b = get(f"/v1/appStoreVersions/{vid}/build").get("data")
        print("BUILD attached", b and b["attributes"].get("version"))
    except urllib.error.HTTPError:
        pass
    rd = get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if not rd:
        raise SystemExit("no App Review details on this version (contact name/phone missing)")
    patch("appStoreReviewDetails", rd["id"], {"notes": NOTES})
    print("REVIEW NOTES set")
    if os.environ.get("ATTACHMENT"):
        upload_attachment(rd["id"], os.path.join(ROOT, os.environ["ATTACHMENT"]))
    state = ver["attributes"].get("appStoreState")
    if os.environ.get("SUBMIT") == "1" and state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
        print("ALREADY SUBMITTED (" + state + ") – the update applies to the open submission")
    elif os.environ.get("SUBMIT") == "1":
        resubmit(app_id, vid)
    else:
        print("NOT SUBMITTED (submit=false)")


if __name__ == "__main__":
    sys.exit(main())
