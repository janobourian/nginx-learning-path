# Module 14: WebRTC Peer Connections, DataChannels & MediaStreams

**Track:** Modern JavaScript — Frontend Architecture & Web APIs
**Category:** Peer-to-Peer Networking, WebRTC & Real-Time Media

---

## 1. What Is WebRTC?

**WebRTC (Web Real-Time Communication)** is an open W3C standard that enables direct **Peer-to-Peer (P2P)** audio, video, and data communication between web browsers **without routing media packets through an intermediary server**.

```text
WebRTC Direct P2P Architecture:
[Browser Peer A] ◄────────────────(Signaling Server: Handshake Only)────────────────► [Browser Peer B]
        │                                                                                     │
        ▼ (Direct Encrypted Peer-to-Peer Media & Data Stream over SRTP / SCTP / UDP)          ▼
        └─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The 3 Core WebRTC APIs

```text
┌─────────────────────────────────────────────────────────────┐
│                     The WebRTC API Trilogy                  │
├────────────────────┬────────────────────────────────────────┤
│ **`MediaDevices`** │ Captures microphone, camera, and       │
│                    │ screen share (`getUserMedia`).         │
├────────────────────┼────────────────────────────────────────┤
│ **`RTCPeerConnection`**│ Manages the lifecycle of P2P audio/│
│                    │ video streaming and NAT traversal.     │
├────────────────────┼────────────────────────────────────────┤
│ **`RTCDataChannel`**│ Ultra-low-latency peer-to-peer data   │
│                    │ transport (SCTP protocol over UDP).    │
└────────────────────┴────────────────────────────────────────┘
```

---

## 3. The Signaling Handshake & NAT Traversal (STUN / TURN)

Because most computers sit behind home routers, firewalls, and NATs, two browsers cannot connect directly without exchanging network descriptions through a temporary **Signaling Server** (WebSocket):

```text
┌─────────────────────────────────────────────────────────────┐
│                 WebRTC Signaling & ICE Handshake            │
├─────────────────────────────────────────────────────────────┤
│ 1. Peer A creates an **SDP Offer** (Codec/Resolution info). │
│ 2. Peer A sends Offer to Peer B via Signaling Server.       │
│ 3. Peer B receives Offer and sends back an **SDP Answer**.  │
│ 4. Both peers query **STUN Servers** to discover their own  │
│    public IP addresses & ports.                             │
│ 5. Peers exchange **ICE Candidates** to establish the       │
│    fastest direct P2P UDP route.                            │
│ 6. If direct P2P is blocked by symmetric NAT, fallback to a │
│    **TURN Relay Server**.                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Complete WebRTC P2P Video Call Implementation

```javascript
// src/webrtc/webrtc_call.js

const iceServers = [
  { urls: 'stun:stun.l.google.com:19302' }, // Free Google STUN Server
];

export class WebRtcCallSession {
  constructor(signalingSocket) {
    this.socket = signalingSocket;
    this.peerConnection = new RTCPeerConnection({ iceServers });
    this.localStream = null;

    this._initPeerListeners();
    this._initSignalingListeners();
  }

  async startCamera(localVideoElement, remoteVideoElement) {
    // 1. Capture Camera & Microphone:
    this.localStream = await navigator.mediaDevices.getUserMedia({
      video: { width: 1280, height: 720 },
      audio: true,
    });

    localVideoElement.srcObject = this.localStream;

    // 2. Add local audio/video tracks to PeerConnection:
    this.localStream.getTracks().forEach((track) => {
      this.peerConnection.addTrack(track, this.localStream);
    });

    // 3. Receive Remote Peer's MediaStream:
    this.peerConnection.ontrack = (event) => {
      console.log('[WebRTC]: Received remote media track!');
      remoteVideoElement.srcObject = event.streams[0];
    };
  }

  _initPeerListeners() {
    // Collect local ICE candidates and send to remote peer via signaling socket:
    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.socket.send(JSON.stringify({ type: 'ice-candidate', candidate: event.candidate }));
      }
    };
  }

  _initSignalingListeners() {
    this.socket.onmessage = async (event) => {
      const msg = JSON.parse(event.data);

      if (msg.type === 'offer') {
        // Peer B receives Offer:
        await this.peerConnection.setRemoteDescription(new RTCSessionDescription(msg.offer));
        const answer = await this.peerConnection.createAnswer();
        await this.peerConnection.setLocalDescription(answer);

        this.socket.send(JSON.stringify({ type: 'answer', answer }));
      } else if (msg.type === 'answer') {
        // Peer A receives Answer:
        await this.peerConnection.setRemoteDescription(new RTCSessionDescription(msg.answer));
      } else if (msg.type === 'ice-candidate') {
        // Add remote peer's candidate:
        await this.peerConnection.addIceCandidate(new RTCIceCandidate(msg.candidate));
      }
    };
  }

  // Peer A initiates the call:
  async makeCall() {
    const offer = await this.peerConnection.createOffer();
    await this.peerConnection.setLocalDescription(offer);
    this.socket.send(JSON.stringify({ type: 'offer', offer }));
  }

  hangUp() {
    this.localStream?.getTracks().forEach((t) => t.stop());
    this.peerConnection.close();
  }
}
```

---

## 5. High-Speed Peer-to-Peer Data with `RTCDataChannel`

For multiplayer gaming, collaborative whiteboards, or direct file sharing without server bandwidth costs:

```javascript
// Peer A creates DataChannel:
const dataChannel = peerConnection.createDataChannel('gameTelemetry', {
  ordered: true, // Guarantees in-order packet delivery (TCP-like) or false (UDP-like)
});

dataChannel.onopen = () => {
  console.log('P2P DataChannel open! Ready for ultra-low latency messaging.');
  dataChannel.send(JSON.stringify({ playerX: 450, playerY: 200 }));
};

dataChannel.onmessage = (e) => {
  console.log('Received direct P2P data:', e.data);
};

// Peer B listens for incoming DataChannel:
peerConnection.ondatachannel = (event) => {
  const receiveChannel = event.channel;
  receiveChannel.onmessage = (e) => {
    console.log('Peer B received data:', e.data);
  };
};
```

---

## Troubleshooting & Best Practices

1. **Always Provide TURN Server Credentials for Enterprise Networks**
   STUN servers fail on strict corporate firewalls and symmetric 4G/5G mobile carriers (estimated ~15% of all connections). Always configure a TURN relay server (e.g. Coturn, Twilio, or Cloudflare Calls) to ensure 100% connection reliability.

2. **Always Stop Camera Tracks on Call Teardown**
   Calling `peerConnection.close()` does NOT turn off the user's hardware webcam indicator light. You **must** iterate through `localStream.getTracks().forEach(t => t.stop())` to release the camera hardware cleanly.
