# Janzeer SDK end-to-end conformance flow

Every official SDK (TypeScript, Dart, Kotlin, Go) implements this flow as an environment-gated test
(`JANZEER_NODE_URL` unset → skipped). The same flow, trimmed, is each SDK's README quickstart, so the
documentation is executable by construction. It runs against the local 4-anchor developer network started
by `e2e/node-up.sh` (a single node does not produce blocks, so finality can only be proven on the 4-node net).

## Environment

| Variable | Default (node-up.sh) | Meaning |
|---|---|---|
| `JANZEER_NODE_URL` | `http://localhost:7019/api/v1/` | REST base (trailing slash) |
| `JANZEER_RPC_URL` | `http://localhost:7019/rpc` | JSON-RPC over HTTP |
| `JANZEER_WS_URL` | `ws://localhost:7029/rpc/ws` | JSON-RPC over WebSocket (a DIFFERENT node than the one the tx is sent to — proves gossip) |
| `JANZEER_E2E_MNEMONIC` | `abandon ×11 about` | faucet wallet (`--janzeer.dev-fund` funds it at genesis) |
| `JANZEER_E2E_RECIPIENT` | `0x598b1301acef3baba6ce25e38dd17b723f7b98b1` | recipient (never spends) |
| `JANZEER_E2E_VALIDATOR_MNEMONIC` | first anchor wallet (from `j_helper/out/anchors.json`, dev net only) | a VALIDATOR wallet — token CREATE is validator-only; examples/tests that create tokens skip when unset |

## Steps and assertions

1. **Derive** `Account.fromMnemonic(JANZEER_E2E_MNEMONIC)` → address `0x06e1c0fa9955a700876f8cb0acc7f13fba9fb8ba`.
2. **Version gate** REST `info/version` → `version == "0.0.2"`, envelope `version == "1.1.0"`; the SDK's `SPEC_VERSION` must match or the test fails early with a clear message.
3. **Account** RPC `janzeer_getAccount(address)` → `balance > 0`; remember `balance0`; `nonce = nextNonce`.
4. **Subscribe first** open WS, `janzeer_subscribe("addressActivity", {addresses:[recipient]})` → subscription id (16 hex chars).
5. **Build + sign** transfer `{to: recipient, amount: "1.25", fee: "0.01", memo: "sdk-e2e-<lang>", nonce, timestamp: now}`. Assert the SDK's `hash` equals double-SHA256 of its own preimage and the signature verifies locally.
6. **Submit via REST** `POST transactions/transfers` → HTTP 201, payload `hash == tx.hash`.
7. **Resubmit via RPC** `janzeer_sendTransfer(sameBody)` → `{hash, status:"PENDING"}` (idempotent; still one pending).
8. **Status** `janzeer_getTransactionByHash(hash).status ∈ {PENDING, FINAL}`.
9. **Finality** `waitForFinality(hash, 60000)` on the WS node or RPC → `status == "FINAL"`, `blockHeight > 0`, `receipt.successful == true`.
10. **Balance** REST `wallets/{address}` == `balance0 − 1.25 − 0.01` compared as exact decimals (never floats).
11. **Notification** a `janzeer_subscription` message with `params.kind == "addressActivity"` and `params.result.transaction.hash == hash` arrived within 60 s; `janzeer_unsubscribe(id)` → `true`; close the socket.
12. **Negative: nonce gap** submit a fresh transfer with `nonce + 10` → REST 400 whose payload has `type == "INVALID_NONCE"` and the SDK raises `NonceMismatchError{expected, got}` (RPC: `-32001`, `data.type == "INVALID_NONCE"`).
13. **Negative: bad signature** the same body with another tx's signature → `TxRejectedError` with `type == "INCORRECT_SIGNATURE"`.
14. **Negative: bad address** `janzeer_getBalance("0x12")` → `RpcError` code `-32602`.

Each language uses its own memo (`sdk-e2e-ts`, `sdk-e2e-dart`, `sdk-e2e-kotlin`, `sdk-e2e-go`) so `run-all.sh` can run them back-to-back against one network without the addressActivity assertions cross-matching.

## Pass criteria

All 14 steps green; total wall time under 3 minutes on the dev box (finality takes one or two 15-second slots).
