# Omiai

Omiai is the Phoenix signaling relay used by XiaDianxin/Sankaku peers.

## Key Capabilities

- Authenticated websocket signaling socket at `/ws/sankaku` (`OmiaiWeb.SankakuSocket`)
- Peer channel topics: `peer:<public_key>` (`OmiaiWeb.SignalingChannel`)
- Dual event contract routing (canonical SDP events + legacy aliases)
- Presence tracking for online peer fast-fail behavior
- Quicdial runtime registry: `public_key => peer_ip` while peer is connected
- `resolve_quicdial` channel event for resolving a target Quicdial code to current IP
- mDNS advertisement for zero-config LAN discovery (`_omiai._tcp`)

## Quicdial Resolution Flow

1. Peer connects websocket with `public_key`.
2. Socket extracts `peer_data` IP from endpoint `connect_info`.
3. `OmiaiWeb.QuicdialRegistry` stores `%{public_key => ip}` for that socket process.
4. Caller pushes:

```json
{
  "event": "resolve_quicdial",
  "payload": { "code": "target_public_key" }
}
```

5. Channel replies:
   - Success: `%{ip: "203.0.113.10"}`
   - Failure: `%{"reason" => "offline"}`

IPv4 and IPv6 peer tuples are both supported when extracting `peer_data.address`.

## Startup Registration Handshake

After websocket upgrade, clients should push this payload to `register_startup`:

```json
{
  "public_key": "alice_public_key",
  "session_token": "session-token",
  "sig_ts": "1741205660123",
  "sig_nonce": "f1ec6d6a-18c7-43d4-b5b4-c73c97f4a70e"
}
```

Omiai refreshes Presence metadata and Quicdial IP mapping on that call.

## mDNS Broadcast

Omiai advertises itself on LAN as:

- Service type: `_omiai._tcp`
- Instance: `Omiai_Local_Node`
- Port: endpoint HTTP port (default `4000`)
- TXT payload includes websocket path: `/ws/sankaku/websocket`

## Local Development

```bash
mix setup
mix phx.server
```

Dev endpoint binds on `0.0.0.0:4000` for LAN/iOS device testing.
Websocket endpoint is `ws://<LAN-IP>:4000/ws/sankaku/websocket`.

## Testing

```bash
mix test
```

Channel tests cover:
- Canonical/legacy event routing
- Presence lifecycle
- Quicdial resolve success/offline behavior
