"""Fill in the CitySwing App Store listing (DRAFT only – never submits).

Run by .github/workflows/appstore_listing.yml (the API key lives in GitHub
secrets). Env: KEY_ID, ISSUER, KEY (p8 contents), VERSION (e.g. 1.0.0),
BUILD (build number to attach, optional), SHOTS=1 to (re)upload screenshots.

Sets, for the iOS version VERSION (created if missing):
  * every localisation: description, keywords, promotional text, support and
    marketing URLs
  * app info localisations: subtitle, privacy policy URL
  * categories (Games → Action, Adventure), copyright
  * App Review notes (+ contact email; no demo account)
  * the build, if BUILD is given and processed
  * screenshots from store/screenshots/{iphone69,ipad13}/*.jpg (replacing
    what's in those sets)
Leaves to the developer (Apple requires their own attestation or details):
price, App Privacy answers, age rating questionnaire, review contact
name/phone, and pressing Submit for Review.
"""
import glob
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.musastudios.cityswing"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DESCRIPTION = open(os.path.join(ROOT, "store", "description.txt")).read().strip()
KEYWORDS = "swing,web,rope,parkour,rooftop,open world,city,physics,freerun,time trial,speed,flying,traversal"
PROMO = ("Fire a web, swing through the skyline and never touch the street. A whole coastal city to fly "
         "through: time trials, rooftop jobs and homes to earn.")
SUBTITLE = "Swing a whole city your way"
SUPPORT = "https://musastudios.co.uk/support"
MARKETING = "https://musastudios.co.uk/portfolio/"
PRIVACY = "https://musastudios.co.uk/privacy/cityswing"
COPYRIGHT = "2026 Musa Studios"
NOTES = open(os.path.join(ROOT, "store", "review_notes.txt")).read().strip()
SETS = {"iphone69": "APP_IPHONE_67", "ipad13": "APP_IPAD_PRO_3GEN_129"}
BOOL_HINTS = ("gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls",
              "ageAssurance", "userGeneratedContent", "advertising", "healthOrWellnessTopics")


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ISSUER"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      os.environ["KEY"], algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, raw=None, headers=None, url=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = {"Authorization": "Bearer " + token(), "Content-Type": "application/json"}
    if headers:
        h = headers
    req = urllib.request.Request(url or API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read()
            return json.loads(txt) if txt and r.headers.get("Content-Type", "").startswith("application/json") else {}
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")
        print(f"HTTP {e.code} {method} {path or url}: {msg[:1500]}")
        raise


def get(path):
    return call("GET", path)


def patch(kind, id_, attrs, rels=None):
    body = {"data": {"type": kind, "id": id_, "attributes": attrs}}
    if rels:
        body["data"]["relationships"] = rels
    return call("PATCH", f"/v1/{kind}/{id_}", body)


def main():
    version = os.environ["VERSION"]
    app = get(f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
    app_id = app["id"]
    print("APP", app_id, app["attributes"].get("name"), "primary locale", app["attributes"].get("primaryLocale"))

    # --- the version ---------------------------------------------------
    vs = get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    ver = next((v for v in vs if v["attributes"]["versionString"] == version), None)
    editable = [v for v in vs if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if ver is None and editable:
        ver = editable[0]
        patch("appStoreVersions", ver["id"], {"versionString": version})
        print("VERSION renamed", ver["attributes"]["versionString"], "->", version)
    elif ver is None:
        ver = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("VERSION created", version)
    vid = ver["id"]
    print("VERSION", version, ver["attributes"].get("appStoreState"))
    patch("appStoreVersions", vid, {"copyright": COPYRIGHT, "releaseType": "MANUAL"})

    # --- version localisations ----------------------------------------------
    for loc in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
        patch("appStoreVersionLocalizations", loc["id"], {"description": DESCRIPTION, "keywords": KEYWORDS,
              "promotionalText": PROMO, "supportUrl": SUPPORT, "marketingUrl": MARKETING})
        print("LOCALISATION", loc["attributes"]["locale"], "text set")

    # --- app info: subtitle, privacy URL, categories ------------------------
    infos = get(f"/v1/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") != "READY_FOR_SALE"), infos[0])
    for loc in get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
        patch("appInfoLocalizations", loc["id"], {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY})
        try:
            patch("appInfoLocalizations", loc["id"], {"name": "CitySwing"})
            print("APP NAME CitySwing")
        except urllib.error.HTTPError:
            print("APP NAME kept (CitySwing not accepted – taken or locked)")
        print("APP INFO", loc["attributes"]["locale"], "subtitle + privacy URL set")
    try:
        patch("appInfos", info["id"], {}, {
            "primaryCategory": {"data": {"type": "appCategories", "id": "GAMES"}},
            "primarySubcategoryOne": {"data": {"type": "appCategories", "id": "GAMES_ACTION"}},
            "primarySubcategoryTwo": {"data": {"type": "appCategories", "id": "GAMES_ADVENTURE"}}})
        print("CATEGORIES Games / Action, Adventure")
    except urllib.error.HTTPError:
        print("CATEGORIES not set (set them in App Store Connect)")

    # --- App Review notes -------------------------------------------------
    try:
        rd = get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    except urllib.error.HTTPError:
        rd = None
    attrs = {"notes": NOTES, "demoAccountRequired": False, "contactEmail": "support@musastudios.co.uk"}
    try:
        if rd:
            patch("appStoreReviewDetails", rd["id"], attrs)
        else:
            call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                 "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("REVIEW NOTES set")
    except urllib.error.HTTPError:
        # Apple won't create it without the contact's name and phone.
        print("REVIEW NOTES not set: App Review needs contact first/last name + phone first "
              "(paste store/review_notes.txt into Notes)")

    # --- build --------------------------------------------------------------
    build = os.environ.get("BUILD", "").strip()
    if build:
        bs = get(f"/v1/builds?filter[app]={app_id}&filter[version]={build}&filter[preReleaseVersion.platform]=IOS")["data"]
        if bs and bs[0]["attributes"]["processingState"] == "VALID":
            call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                 {"data": {"type": "builds", "id": bs[0]["id"]}})
            print("BUILD", build, "attached")
        else:
            print("BUILD", build, "not attachable yet:", bs[0]["attributes"]["processingState"] if bs else "not found")

    # --- screenshots ---------------------------------------------------------
    if os.environ.get("SHOTS") == "1":
        for loc in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
            sets = get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
            for folder, dtype in SETS.items():
                files = sorted(glob.glob(os.path.join(ROOT, "store", "screenshots", folder, "*.jpg")))
                if not files:
                    continue
                s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == dtype), None)
                if s is None:
                    s = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": dtype},
                        "relationships": {"appStoreVersionLocalization": {"data": {
                            "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
                for old in get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
                    call("DELETE", f"/v1/appScreenshots/{old['id']}")
                for f in files:
                    blob = open(f, "rb").read()
                    sh = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                        "attributes": {"fileName": os.path.basename(f), "fileSize": len(blob)},
                        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})["data"]
                    for op in sh["attributes"]["uploadOperations"]:
                        part = blob[op["offset"]:op["offset"] + op["length"]]
                        call(op["method"], "", raw=part, url=op["url"],
                             headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                    patch("appScreenshots", sh["id"], {"uploaded": True,
                          "sourceFileChecksum": hashlib.md5(blob).hexdigest()})
                    print("SCREENSHOT", loc["attributes"]["locale"], dtype, os.path.basename(f))
        # Report processing state.
        time.sleep(20)
        for loc in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
            for s in get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
                for x in get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
                    st = x["attributes"].get("assetDeliveryState") or {}
                    print("SHOT STATE", s["attributes"]["screenshotDisplayType"], x["attributes"]["fileName"],
                          st.get("state"), st.get("errors") or "")

    # --- content rights (third-party CC assets, licensed and credited) --------
    try:
        patch("apps", app_id, {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"})
        print("CONTENT RIGHTS uses third-party content (licensed, credited in game)")
    except urllib.error.HTTPError:
        print("CONTENT RIGHTS not set")

    # --- age rating: every content descriptor "none" ---------------------------
    try:
        ar = get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
        attrs = {}
        for k, v in ar["attributes"].items():
            if k in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
                     "developerAgeRatingInfoUrl"):
                continue
            if isinstance(v, bool) or (v is None and k in BOOL_HINTS):
                attrs[k] = False
            elif isinstance(v, str) or v is None:
                attrs[k] = "NONE"
        try:
            patch("ageRatingDeclarations", ar["id"], attrs)
        except urllib.error.HTTPError:
            # Unknown enum for some new field: retry one key at a time.
            for k, v in attrs.items():
                try:
                    patch("ageRatingDeclarations", ar["id"], {k: v})
                except urllib.error.HTTPError:
                    try:
                        patch("ageRatingDeclarations", ar["id"], {k: not v if isinstance(v, bool) else False})
                    except urllib.error.HTTPError:
                        print("AGE RATING could not set", k)
        now = get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
        print("AGE RATING", json.dumps(now))
    except urllib.error.HTTPError:
        print("AGE RATING not set (fill the questionnaire in App Store Connect)")

    # --- price: £2.99, base territory United Kingdom ------------------------------
    try:
        point = None
        url = f"/v1/apps/{app_id}/appPricePoints?filter[territory]=GBR&limit=200"
        while url and point is None:
            page = call("GET", "", url=url if url.startswith("http") else API + url)
            for pp in page["data"]:
                if pp["attributes"].get("customerPrice") in ("2.99", "2.990"):
                    point = pp["id"]
                    break
            url = page.get("links", {}).get("next")
        if point:
            call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "GBR"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price0}"}]}}},
                "included": [{"type": "appPrices", "id": "${price0}", "attributes": {"startDate": None},
                              "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point}}}}]})
            print("PRICE £2.99 (GBR base, other territories follow Apple's equalisation)")
        else:
            print("PRICE point £2.99 not found")
    except urllib.error.HTTPError:
        print("PRICE not set (Paid Apps agreement must be active; set it in Pricing and Availability)")

    # --- availability -----------------------------------------------------------
    try:
        av = call("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
        print("AVAILABILITY exists:", av["data"]["attributes"])
    except urllib.error.HTTPError:
        try:
            terrs = []
            url = API + "/v1/territories?limit=200"
            while url:
                page = call("GET", "", url=url)
                terrs += [t["id"] for t in page["data"]]
                url = page.get("links", {}).get("next")
            inc = [{"type": "territoryAvailabilities", "id": f"${{t{i}}}", "attributes": {"available": True},
                    "relationships": {"territory": {"data": {"type": "territories", "id": t}}}}
                   for i, t in enumerate(terrs)]
            call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities",
                 "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": x["id"]} for x in inc]}}},
                 "included": inc})
            print("AVAILABILITY all", len(terrs), "territories")
        except urllib.error.HTTPError:
            print("AVAILABILITY not set (Pricing and Availability page)")

    # --- what Apple still needs ---------------------------------------------------
    try:
        rd = get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data") or {}
    except urllib.error.HTTPError:
        rd = {}
    ra = rd.get("attributes", {})
    missing = [k for k in ("contactFirstName", "contactLastName", "contactPhone") if not ra.get(k)]
    print("STILL NEEDED: App Privacy questionnaire (not in the API)" + (", review contact " + ", ".join(missing) if missing else ""))
    print("DONE – draft only; nothing was submitted for review.")


if __name__ == "__main__":
    sys.exit(main())
