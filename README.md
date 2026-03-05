# Omiai

Omiai is the Phoenix signaling relay used by XiaDianxin/Sankaku peers.

## Key Capabilities

- Authenticated websocket signaling socket at `/ws/sankaku` (`OmiaiWeb.SankakuSocket`)
- Peer channel topics: `peer:<public_key>` (`OmiaiWeb.SignalingChannel`)
- Dual event contract routing (canonical SDP events + legacy aliases)
- Presence tracking for online peer fast-fail behavior
- Quicdial runtime registry: `public_key => peer_ip` while peer is connected
- `resolve_quicdial` channel event for resolving a target Quicdial code to current IP

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

## Local Development

```bash
mix setup
mix phx.server
```

Endpoint defaults to `http://localhost:4000`.
Websocket endpoint is `ws://localhost:4000/ws/sankaku/websocket`.

## Testing

```bash
mix test
```

Channel tests cover:
- Canonical/legacy event routing
- Presence lifecycle
- Quicdial resolve success/offline behavior
