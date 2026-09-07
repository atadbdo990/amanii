{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": __PORT__,
      "listen": "0.0.0.0",
      "tag": "__INBOUND_TAG__",
      "protocol": "__PROTO__",
      "settings": {
        "clients": [
          {
            "id": "__USER_ID__",
            "password": "__USER_ID__",
            "email": "__INBOUND_TAG__@amani",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "__NETWORK__",
        "security": "none",
        "wsSettings": {
          "path": "__WS_PATH__",
          "host": "__HOST__"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "port": 10085,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "streamSettings": { "sockopt": { "tcpFastOpen": true } },
      "tag": "direct"
    },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "stats": {},
  "api": { "tag": "api", "services": ["StatsService"] },
  "routing": {
    "rules": [
      { "inboundTag": ["api"], "outboundTag": "api", "type": "field" },
      { "protocol": ["bittorrent"], "outboundTag": "block", "type": "field" }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 65536,
        "uplinkCapacity": __SPEED_LIMIT__,
        "downlinkCapacity": __SPEED_LIMIT__
      }
    },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true }
  }
}
