# Connecting to an OpenClaw gateway

Everything needed to connect this client, learned by connecting to a real
gateway and reading its rejections — none of it is in OpenClaw's published
docs, and the `@openclaw/gateway-protocol` npm package that claims to ship the
schema is a `0.0.0` placeholder.

## The connect handshake

The gateway speaks first with a `connect.challenge` event, then the client
answers a `connect` request. Both the nonce and timestamp from the challenge go
into a signature, so there is nothing to send until the server speaks.

Fields the server validates, and the exact error each wrong value returns:

| Field | Rule | Error when wrong |
|---|---|---|
| `client.mode` | one of `cli` `ui` `node` | `must be equal to one of the allowed values` |
| `role` | one of `operator` `node` (a *separate* set from mode) | `invalid role` |
| `client.id` | closed set incl. `cli` `gateway-client` `openclaw-macos` `openclaw-ios` `node-host` `test` | `must be equal to one of the allowed values` |
| `client.platform` | non-empty string | `must not have fewer than 1 characters` |
| `client.deviceFamily` | optional, on **`client`** not `device` | `unexpected property 'deviceFamily'` if on `device` |
| `device.id` | **hex SHA-256 of the raw 32-byte Ed25519 public key** | `DEVICE_AUTH_DEVICE_ID_MISMATCH` |
| `device.publicKey` | raw key, **unpadded base64url** | signature failures |
| `device.signature` | over the v3 payload, unpadded base64url | `device identity changed` (looks like a key fault, is not) |

The signed payload (`buildDeviceAuthPayloadV3`), joined with `|`, compared
byte-for-byte, empty fields keeping their pipes, `platform`/`deviceFamily`
lowercased and nothing else:

```
v3|deviceId|clientId|clientMode|role|scopes(csv)|signedAtMs|token|nonce|platform|deviceFamily
```

**The token is field 8 — inside the signature.** A client that picks its
credential after signing sends a valid signature over the wrong string, and the
gateway reports it as a *device identity* problem, which sends you debugging the
wrong half. `_signatureToken` in `gateway.dart` picks the presented credential
(`token` → `deviceToken` → `bootstrapToken`) before signing.

## The auth ladder (what each error means)

Observed by presenting each credential form to the live gateway. These are
*progress markers* — each one means the previous gate passed:

1. no `auth` → `AUTH_TOKEN_MISSING`
2. wrong token → `AUTH_TOKEN_MISMATCH`
3. correct `gateway.auth.token`, unknown device → `NOT_PAIRED / PAIRING_REQUIRED: device is not approved yet`
4. correct token, stale on-disk identity → `PAIRING_REQUIRED: device identity changed and must be re-approved`
5. `bootstrapToken` that is not a live setup code → `AUTH_BOOTSTRAP_TOKEN_INVALID: scan a fresh setup code`
6. paired device → `hello-ok`

`ClawRpcException` exposes `needsGatewayToken`, `gatewayTokenWrong`,
`needsPairing` so a UI can tell these apart. OpenClaw's **own** CLI and `doctor`
produce (3)/(4) identically for an unpaired identity — this is the pairing
model, not a client bug.

## Pairing is a human gate

Reaching `hello-ok` needs a device the gateway has approved. Three ways in, all
requiring an operator or a freshly minted code — none manufacturable
client-side:

- an operator approves the pending device: `openclaw devices approve <deviceId>`
  (run where an operator connection exists — e.g. on the gateway host)
- the client presents a `bootstrapToken` that is a live setup code (QR / 6-digit)
- OpenClaw app → Settings → Devices → Approve

The device key is generated once and **persisted** (`--seed`): a device that
regenerates its key each launch must be re-approved each launch.

## Finishing, once the device is approved

```bash
cd packages/openclaw_protocol
CLAW_URL=wss://<host>/ \
CLAW_TOKEN=<gateway.auth.token> \
CLAW_COOKIE='<reverse-proxy cookie, if any>' \
  dart run bin/connect.dart --seed <path to the persisted seed>
```

It connects, lists sessions, sends a message, and streams the reply. Before
approval it stops at step (3) above with `→ approve device <id>, then re-run`.

The gateway token authenticates the *client*; a reverse-proxy cookie (e.g.,
reverse-proxy auth) authenticates the *tunnel* and is never the gateway credential. Neither is
ever written to disk — only the device seed is, and a seed is useless without an
approved pairing.
