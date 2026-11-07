#!/bin/bash
#
# EAS 대체 경로(eas-release.sh)용 iOS 배포 인증서·App Store 프로필을 App Store Connect API로 만든다.
# 대화형 단계가 없다(eas credentials 대신). 처음 한 번, 또는 인증서가 만료됐을 때(1년) 돌린다.
#
#   bash scripts/expo-release/setup-ios-signing.sh [출력 폴더]   (기본 ~/.config/<번들 ID>/ios-dist)
#
# 설정 eas.asc_key_path·asc_key_id·asc_issuer_id(Admin 키)와 ios.bundle_id를 쓴다.
# 만든 뒤 설정 eas.ios_p12·ios_p12_password_file·ios_profile에 넣을 경로를 출력한다.
# 배포 인증서는 팀당 개수 한도(보통 3)가 있다 — 이미 차 있으면 Apple이 거절한다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "$0")/lib.sh"
expand() { python3 -c 'import os,sys;print(os.path.expanduser(sys.argv[1]))' "$1"; }

BUNDLE_ID=$(cfg ios.bundle_id)
D=$(expand "${1:-~/.config/$BUNDLE_ID/ios-dist}")
KEY=$(expand "$(cfg eas.asc_key_path)"); KID=$(cfg eas.asc_key_id); ISS=$(cfg eas.asc_issuer_id)
[ -f "$KEY" ] && [ -n "$KID" ] && [ -n "$ISS" ] || { echo "설정 eas.asc_key_path·asc_key_id·asc_issuer_id가 필요하다" >&2; exit 1; }
[ ! -f "$D/dist.p12" ] || { echo "$D/dist.p12가 이미 있다 — 다시 만들려면 그 폴더를 치우고 돌려라" >&2; exit 1; }

mkdir -p "$D"; chmod 700 "$D"
openssl genrsa -out "$D/dist.key" 2048 2>/dev/null; chmod 600 "$D/dist.key"
openssl req -new -key "$D/dist.key" -out "$D/dist.csr" -subj "/CN=$BUNDLE_ID EAS Distribution" 2>/dev/null

python3 - "$D" "$KEY" "$KID" "$ISS" "$BUNDLE_ID" <<'PY'
import base64, json, os, secrets, subprocess, sys, time, urllib.parse, urllib.request
D, key, kid, iss, bundle = sys.argv[1:]
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def token():
    now = int(time.time())
    msg = f'{b64(json.dumps({"alg":"ES256","kid":kid,"typ":"JWT"}).encode())}.{b64(json.dumps({"iss":iss,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}).encode())}'
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=msg.encode(), capture_output=True, check=True).stdout
    # DER ECDSA(SEQUENCE{INTEGER r, INTEGER s}) → r||s 32바이트씩
    i = 2 + (1 if der[1] & 0x80 else 0); out = b""
    for _ in range(2):
        n = der[i + 1]; v = der[i + 2:i + 2 + n].lstrip(b"\0"); out += v.rjust(32, b"\0"); i += 2 + n
    return f"{msg}.{b64(out)}"

def api(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect {method} {path}: {e.code} {e.read().decode()[:400]}")

ids = api("GET", "/v1/bundleIds?" + urllib.parse.urlencode({"filter[identifier]": bundle}))["data"]
bid = next((x["id"] for x in ids if x["attributes"]["identifier"] == bundle), None) or sys.exit(f"번들 ID {bundle}가 없다")
cert = api("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
    "certificateType": "DISTRIBUTION", "csrContent": open(f"{D}/dist.csr").read()}}})["data"]
open(f"{D}/dist.cer", "wb").write(base64.b64decode(cert["attributes"]["certificateContent"]))
prof = api("POST", "/v1/profiles", {"data": {"type": "profiles",
    "attributes": {"name": f"{bundle} EAS AppStore {time.strftime('%Y%m%d')}", "profileType": "IOS_APP_STORE"},
    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                      "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
open(f"{D}/appstore.mobileprovision", "wb").write(base64.b64decode(prof["attributes"]["profileContent"]))
fd = os.open(f"{D}/p12-password.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, secrets.token_urlsafe(24).encode()); os.close(fd)
subprocess.run(["openssl", "x509", "-inform", "DER", "-in", f"{D}/dist.cer", "-out", f"{D}/dist.pem"], check=True)
subprocess.run(["openssl", "pkcs12", "-export", "-legacy", "-inkey", f"{D}/dist.key", "-in", f"{D}/dist.pem",
                "-out", f"{D}/dist.p12", "-passout", f"file:{D}/p12-password.txt"], check=True)
os.chmod(f"{D}/dist.p12", 0o600)
print(f"인증서 {cert['id']} (만료 {cert['attributes']['expirationDate'][:10]}), 프로필 {prof['id']}")
PY

echo "설정 .expo-release.json eas에 넣는다:"
printf '  "ios_p12": "%s",\n  "ios_p12_password_file": "%s",\n  "ios_profile": "%s"\n' \
  "$D/dist.p12" "$D/p12-password.txt" "$D/appstore.mobileprovision" | sed "s|$HOME|~|g"
