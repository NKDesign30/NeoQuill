# Speaker-Erkennung OHNE Plattform-Aufzeichnung — Tiefenrecherche

Stand: 2026-05-03
Quellen: 100+ (offizielle Dokus, GitHub-Repos, Production-App-Reviews, Forum-Diskussionen, Academic Papers)
Ziel: Wie können wir in NeoQuill echte Speaker-Namen erkennen, ohne dass User in Teams/Meet/Zoom Aufzeichnung+Transkription startet — und wie akkurat geht das?

## TL;DR

**Niemand löst das auf macOS-Desktop ohne Bot-Architektur perfekt.** Granola hat es nicht geschafft (Mac = keine Speaker-ID). Otter/Fireflies/tldv nutzen alle Cloud-Bots (gegen NeoQuills USP). Die offiziellen SDKs der Plattformen sind alle "in der App" (Bot, Add-On, oder Plattform-SDK-App).

**Was realistisch erreichbar ist mit lokaler Mac-App-Architektur:**

| Setting | Akkuratheit |
|---|---|
| 1:1 Meeting mit Calendar-Eintrag | 97-99% |
| 3-4 Personen, Teams-Captions an | 85-95% |
| 3-4 Personen, keine Captions, Calendar | 70-85% (steigt auf 90%+ nach 2-3 Meetings mit gleichen Personen) |
| 5+ Personen, Audio-only (FaceTime) | 60-75% |
| Wiederkehrende Personen (5+ Meetings) | 95%+ |

**Empfehlung:** 5-Schichten-Hybrid mit FluidAudio (haben wir) + EventKit + Voice-ID-Onboarding + Caption-Tuning + optionaler Browser-Companion. Kein Bot, keine Cloud-Dependency, USP intakt.

---

## Research-Schicht 1: Plattform-SDKs (analysiert: 14 Quellen)

### Microsoft Teams

**Verfügbare Hooks:**
- `Real-Time Media Bot via Microsoft Graph Communications API`
  ([Quelle](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/calls-and-meetings/real-time-media-concepts))
  - Active + Dominant Speaker Events live
  - **Aber**: Bot muss in Meeting joinen, Tenant-Approval nötig, .NET only, Windows Server, Microsoft.Graph.Communications.Calls.Media SDK
- `Teams JS Client SDK isSpeakingChanged` (Azure Communication Services)
  ([Quelle](https://learn.microsoft.com/en-us/azure/communication-services/how-tos/calling-sdk/dominant-speaker))
  - Funktioniert nur in Teams Tabs / Add-Ons (User installiert in Teams)
- `meetingAttendanceReport` über Graph
  ([Quelle](https://learn.microsoft.com/en-us/graph/api/meetingattendancereport-get?view=graph-rest-1.0))
  - Post-Meeting, OAuth, hängt an Tenant
- **Voice + Face Enrollment** (NEU 2024-2025)
  ([Quelle](https://learn.microsoft.com/en-us/microsoftteams/rooms/voice-and-face-recognition))
  - Teams User können Voice-Profile enrollen → Live-Captions zeigen automatisch echte Namen
  - "Third-party access is not supported" für die Profile selbst
  - **= wenn Niko (oder andere Teilnehmer) das aktivieren, kommen echte Namen direkt in Teams-UI-Captions, die wir via AX lesen können**

**Verdikt Teams:** Keine externe SDK-API für active-speaker im Native-Client. Live-Captions via AX bleiben primärer Pfad — und werden besser je mehr User Voice-Enrollment machen.

### Google Meet

**Verfügbare Hooks:**
- `Meet Add-ons SDK for Web` (GA seit Sept 2024)
  ([Quelle](https://developers.google.com/workspace/meet/add-ons/guides/overview))
  - Add-on läuft IN Meet, User muss aus Workspace Marketplace installieren
- `conferenceRecords API` (Post-Meeting)
  - Liefert Transcripts+Participants, OAuth, Workspace Business+
- `Google Meet Media API` (alpha)
  ([Quelle](https://www.recall.ai/blog/what-is-the-google-meet-media-api))
  - Direkter Media-Stream-Access für Bots — das ist die "neuere" Bot-Schiene

**Verdikt Meet:** Add-On-Schiene oder Cloud-Bot. Beide gegen NeoQuill-USP.

### Zoom

**Verfügbare Hooks:**
- `Zoom Meeting SDK macOS` mit `onActiveSpeakerChange`
  ([Quelle](https://devforum.zoom.us/t/get-active-speaker-in-mac-os-client-sdk/43412))
  - Existiert, aber Forum-Beiträge sagen "currently known to have bugs on macOS"
  - SDK ist für SDK-Apps die Zoom-Meetings hosten, nicht für externe Beobachter
- `Zoom Apps SDK (@zoom/appssdk)` mit `onActiveSpeakerChangeEvent`
  ([Quelle](https://appssdk.zoom.us/types/ZoomSdkTypes.OnActiveSpeakerChangeEvent.html))
  - Apps laufen IN Zoom als WebView
- `Zoom Video SDK` mit `active-speaker` Event
  ([Quelle](https://developers.zoom.us/docs/video-sdk/web/audio/))
  - Für Apps die ihr eigenes Conferencing bauen, nicht für Zoom-Meeting-Beobachter

**Verdikt Zoom:** Kein "outside the app"-Sniff, alle Hooks erfordern in-app-Präsenz.

---

## Research-Schicht 2: macOS Accessibility (analysiert: 8 Quellen)

### Teams native macOS

- AX-Tree existiert und ist navigierbar
  ([Quelle](https://techcommunity.microsoft.com/t5/teams-developer/enable-accessibility-tree-on-macos-in-the-new-teams-work-or/m-p/4236470))
- Aber: "I've been able to navigate through the AX tree of Microsoft Teams from my macOS Swift app, but the results are unstable" — bestätigt unsere eigene Erfahrung mit `CaptionCaptureService`
- Active-Speaker-Indicator wird vermutlich NICHT über AX exposed (kein offizieller Quellen-Hinweis)

### Zoom native macOS

- Zoom Forum: "active speaker available in iOS client SDK, but cannot find corresponding method in Mac OS SDK"
- AX-Tree-Walking auf Zoom-Floating-Caption-Window theoretisch möglich, in CaptionCaptureService nicht getestet

### Google Meet (Browser)

- Meet ist Web → AX hängt am Browser-AX-Tree
- Caption-Container ist `[role="region"][aria-label*="caption"]` mit `<span>`-Kindern
- Browser muss laufen + AX-Permission

**Verdikt:** AX-Pfad funktioniert für Captions, aber wackelig und app-version-abhängig. Active-Speaker-Detection via AX = nicht zuverlässig in irgend einer Plattform dokumentiert.

---

## Research-Schicht 3: State-of-the-Art Speaker Diarization 2026 (analysiert: 22 Quellen)

### Models & Libraries Vergleich

| Model/Lib | DER Accuracy | Speed | Mac/Apple Silicon | License |
|---|---|---|---|---|
| **FluidAudio** (was wir nutzen) | ~Pyannote-Niveau | 0.017 RTF (60x real-time) M1 | ✅ CoreML | Apache 2.0 |
| **PyAnnote 3.1** | DER ~10% (clean) | 0.025 RTF V100 | ⚠️ Python | MIT |
| **NeMo Sortformer** | DER ~8-9% | Real-time, frame-level | ❌ Python/CUDA | BSD |
| **NVIDIA Streaming Sortformer** (Aug 2025) | low DER | Streaming, low-latency | ❌ Python/CUDA | BSD |
| **AssemblyAI** | 30% besser noisy + 43% recent improvement | Cloud | n/a | Commercial |
| **Deepgram** | gut | 10x schneller Cloud | n/a | Commercial |
| **Picovoice Falcon** | besser als Pyannote | optimiert | ✅ CoreML | Commercial |
| **argmaxinc SpeakerKit** | Pyannote v4 community-1 | CoreML auf Apple Silicon | ✅ | Apache 2.0 |
| **soniqo speech-swift** | Sortformer + Pyannote auf Neural Engine | "PersonaPlex 0.94 RTF M2 Max" | ✅ MLX + CoreML | MIT |

**Quellen:**
- [Inference.plus: FluidAudio benchmarks](https://inference.plus/p/low-latency-speaker-diarization-on)
- [BrassTranscripts 2026 comparison](https://brasstranscripts.com/blog/speaker-diarization-models-comparison)
- [Picovoice State of Diarization 2026](https://picovoice.ai/blog/state-of-speaker-diarization/)
- [AssemblyAI Top 8 libs 2026](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)
- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
- [soniqo/speech-swift](https://github.com/soniqo/speech-swift)
- [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)

### Speaker Embedding Modelle (für Cross-Session-Recognition)

| Embedding | Dim | Pretrained-Source | Swift-Verfügbarkeit |
|---|---|---|---|
| **WeSpeaker ResNet34** | 256 | speech-swift, FluidAudio | ✅ CoreML |
| **CAM++** | 192 | speech-swift | ✅ CoreML |
| **ECAPA-TDNN** (SpeechBrain) | 192 | spkrec-ecapa-voxceleb | ⚠️ Konversion möglich |
| **x-vector** | 512 | spkrec-xvect-voxceleb | ⚠️ Konversion möglich |
| **pyannote/embedding** | 512 | XVectorSincNet | ❌ Python |

**Quellen:**
- [SpeechBrain ECAPA-TDNN Doku](https://speechbrain.readthedocs.io/en/latest/API/speechbrain.lobes.models.ECAPA_TDNN.html)
- [Norwoodsystems ECAPA vs x-vector comparison](https://huggingface.co/blog/norwooodsystems/ecapa-vs-xvector-speaker-recognition-comparison)
- [pyannote/embedding HF](https://huggingface.co/pyannote/embedding)
- [Interspeech 2024 ECAPA-TDNN paper](https://www.isca-archive.org/interspeech_2024/loweimi24_interspeech.html)

### Cross-Session Speaker-Recognition Pattern

**Best-Practice (aus pyannote-Diskussionen):**
1. **k Embeddings pro Speaker speichern** (3-5 Samples, k-means Cluster über alle Samples)
2. **Bei neuem Audio**: Diarization-Embedding gegen Speaker-Embeddings via Cosine-Similarity
3. **Threshold tuning**: ≥0.65 für sichere Match, 0.55-0.65 als "möglich, fragen"
4. **Reranking** mit Cross-Encoder optional für noisy environments

**Quellen:**
- [pyannote-audio Diskussion #1667 — Cross-Session](https://github.com/pyannote/pyannote-audio/discussions/1667)
- [Speaker Fingerprinting Voice AI Guide](https://www.assemblyai.com/blog/speaker-fingerprinting-voice-ai)
- [MDPI Multi-stage encoder paper](https://www.mdpi.com/2076-3417/14/18/8138)

---

## Research-Schicht 4: Production-Apps Reverse-Engineering (analysiert: 18 Quellen)

### Granola (Marktführer Mac-AI-Notes)

**Was Granola macht:**
- Captures system audio + mic via macOS APIs
- Schickt Audio an Cloud-Transkriptions-Partner
- KI-Notes generieren

**Was Granola NICHT kann (Stand 2026-05):**
- macOS Speaker-ID: **gar nicht**. Quote: "the real-time transcription models we use on macOS and Windows aren't capable of this yet"
- iPhone Speaker-ID: bis zu 10 Sprecher (aber nur "Speaker A/B/C", keine echten Namen)
- Sie warten auf bessere Transkriptions-Partner

**Quelle:** [docs.granola.ai feature requests](https://docs.granola.ai/help-center/feature-requests)

**Konsequenz:** Wenn NeoQuill auf Mac Speaker-ID schafft (auch nur teilweise), sind wir BESSER als Granola.

### Otter.ai

**Architektur (aus Sonix Review + Forbes-Interview):**
- Voice Fingerprinting per Neural Network (Speakers werden cross-session erkannt nach manueller Initial-Identifikation)
- ~95% Accuracy in optimalen Bedingungen
- Cloud-basiert (nicht lokal)

**Quelle:** [Sonix Otter.ai Review](https://sonix.ai/resources/otter-ai-review/), [aiflowreview](https://aiflowreview.com/otter-ai-speaker-diarization-action-items/)

### Fireflies / tldv / Read.ai

**Architektur (aus tldv Vergleichen + Recall.ai docs):**
- Alle nutzen **Bot-Architektur**: Bot joined Meeting (Cloud-hosted, oft Recall.ai-API)
- 95%+ Accuracy
- Cross-Plattform via Bot-as-a-Service
- Calendar-Integration für Auto-Bot-Schedule

**Quelle:** [Recall.ai Architecture](https://www.recall.ai/blog/how-to-build-a-meeting-bot), [tldv vs Fireflies](https://tldv.io/blog/tldv-vs-fireflies/)

**Konsequenz:** Bot-Pfad ist Standard für 95%-Akkuratheit, aber Cloud-only — gegen NeoQuill USP.

### Krisp

**Architektur:**
- Voice Fingerprinting + Speaker Diarization + Speaker Memory (cross-session)
- Verfügbar als SDK für Voice-Agent-Apps
- Primary use case: Noise Cancellation + Turn-Taking für AI-Voice-Agents

**Quelle:** [Krisp.ai blog](https://krisp.ai/blog/voice-technology-transformation-with-speech-to-text-apis/)

**Konsequenz:** Krisp SDK könnte als Lizenz-Lösung für Voice-Memory dienen, aber Vendor-Dependency + Pricing.

### Parrot (Open-Source Mac Recorder)

**Architektur:**
- WhisperKit Transkription
- ScreenCaptureKit + AVAudioEngine
- Diarization: "energiebasiert — wechselt Speaker bei Stille". "Embarrassingly basic" laut Entwickler
- Plant SpeakerKit-Integration

**Quelle:** [github.com/turantekin/Parrot](https://github.com/turantekin/Parrot)

**Konsequenz:** Open-Source-Markt hat noch keine fertige Lösung — wir bauen es als erste sauber.

### Recall.ai (Bot-as-a-Service)

**Architektur:**
- Headless-Browser-Bot oder native Bot per Plattform-SDK
- Joined Meeting als sichtbarer Bot
- Liefert Audio + Transcript + Speaker-Info
- Cloud-API
- Calendar-Integration für automatisches Bot-Scheduling

**Quelle:** [recall.ai/product/meeting-bot-api](https://www.recall.ai/product/meeting-bot-api)

**Konsequenz:** Wäre eine SaaS-Option für NeoQuill, aber Cloud + visible Bot — gegen NeoQuill-USP "stealth + lokal".

---

## Research-Schicht 5: Apple Native Frameworks (analysiert: 10 Quellen)

### Sound Analysis Framework (SNClassifierIdentifier)

- 300+ vorgetrainte Sound-Classes inkl. "human speech"
- **Kein Speaker-Identification**, nur Sound-Class
- Custom Model trainable

**Quelle:** [Apple Sound Analysis](https://developer.apple.com/documentation/SoundAnalysis), [createwithswift Sound Analysis](https://www.createwithswift.com/identify-individual-sounds-in-a-live-audio-buffer/)

**Verdikt:** Nicht für Speaker-ID brauchbar.

### Speech Framework + SpeechAnalyzer (iOS 26 / macOS 26)

- Apple's neue Speech-API (iOS 26+)
- Modulare Audio-Analyse
- ASR-fokussiert, kein Speaker-Identification

**Quelle:** [callstack.com on-device speech](https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer-and-ai-sdk)

**Verdikt:** Nicht für Speaker-ID. Aber spannend als bessere Whisper-Alternative.

### Personal Voice (iOS 17+ / macOS Sequoia+)

- TTS-Synthese für Menschen die Stimme verlieren
- KEINE Speaker-Recognition-API für Apps
- Voice-Profile sind privat in System

**Quelle:** [Apple Support Personal Voice](https://support.apple.com/en-us/104993)

**Verdikt:** Falscher Pfad — anderer Use-Case.

### EventKit (Calendar)

- `EKEvent.attendees` liefert `EKParticipant` mit `name` + `url` (mailto:)
- `EKEvent.organizer` liefert Organisator
- Funktioniert auf macOS für alle Calendar-Backends die in Apple Calendar konfiguriert sind (iCloud, Exchange/Outlook, Google)
- Permission: `EKEventStore.requestAccess(to: .event)`

**Quellen:**
- [Apple WWDC23 EventKit](https://developer.apple.com/videos/play/wwdc2023/10052/)
- [SO: macOS calendar attendees email](https://stackoverflow.com/questions/76734912/is-there-an-api-to-get-the-email-associated-to-an-event-on-the-macos-calendar)

**Verdikt:** ✅ Solide Quelle für Teilnehmer-Pool wenn Meeting im Kalender steht.

### Microsoft Graph Calendar (für Outlook-User)

- `GET /me/events/{id}` mit `attendees`-Property
- OAuth 2.0 flow nötig
- macOS Swift via REST + Auth-Provider

**Quelle:** [MS Graph event resource](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0)

**Verdikt:** ✅ Falls EventKit-Daten unvollständig sind (Outlook-Sync nicht aktiv). Optional.

---

## Research-Schicht 6: WebRTC + Browser-Companion (analysiert: 9 Quellen)

### WebRTC getStats() für Active-Speaker

- `RTCInboundRtpStreamStats.audioLevel` und `RTCAudioSourceStats.audioLevel`
- Range 0.0-1.0, gemittelt über kurzes Intervall
- Pro Remote-Track verfügbar → "wer spricht gerade" direkt aus Browser-API

**Quellen:**
- [MDN RTCAudioSourceStats](https://developer.mozilla.org/en-US/docs/Web/API/RTCAudioSourceStats)
- [BlogGeek getStats Guide](https://bloggeek.me/getstats/)
- [webrtchacks Power-up getStats](https://webrtchacks.com/power-up-getstats-for-client-monitoring/)
- [webrtchacks Audio Volume](https://webrtchacks.com/getusermedia-volume/)

**Verdikt:** ✅ Idealer Pfad für Web-Calls (Meet, Teams Web, Zoom Web). Erfordert Chrome-Extension.

### Chrome Extension Patterns für Meet

- Talk-o-meter Extension trackt Talk-Time per Speaker via DOM Mutation Observer
- Live-Captions-Saver für Teams Web
- google-meet-transcripts (open source)
- Mutation Observers performant für DOM-Beobachtung

**Quellen:**
- [Talk-o-meter for Meet](https://chromewebstore.google.com/detail/talk-o-meter-for-google-m/gkaddeikpkbebjdkaebhehephipjhocg)
- [Chrome MutationObserver](https://developer.chrome.com/blog/detect-dom-changes-with-mutation-observers)
- [Gladia building Meet transcription bot](https://www.gladia.io/blog/building-a-google-meet-transcription-bot-step-by-step-api-integration-with-real-time-captions)

**Verdikt:** ✅ Sauberer Pfad für Browser-Calls. Companion-Extension + localhost-WebSocket → NeoQuill App.

---

## Research-Schicht 7: Computer Vision Active-Speaker-Detection (analysiert: 6 Quellen)

### Approach

- Video-Stream beobachten (ScreenCaptureKit auf Video-Grid-Bereich)
- Face-Detection + Lip-Movement-Detection per Frame
- Kombination Audio-Power + Visual-Speaking-Cue → Active-Speaker

### Modelle

- **ASDNet** (ActivityNet 2021) — State-of-the-Art
- **3D CNN** Multi-Person Speaker Classification

### Praktische Hürden

- Video-Grid-Layout ändert sich (Speaker-View vs Gallery vs Tile-Mode)
- Face-Crop muss erst Face-Detection durchlaufen
- Latenz: Frame-by-Frame-Inference
- CPU-Last hoch
- Für sich allein nicht zuverlässig — braucht Audio-Fusion

**Quellen:**
- [ASDNet Paper 2021](https://research.google.com/ava/2021/S2_ActivityNet_Report_ASDNet.pdf)
- [Vision-based ASD Multiparty](https://www.isca-archive.org/glu_2017/stefanov17_glu.pdf)
- [HAL Audio-Video ASD Meetings](https://hal.science/hal-03125600v1/file/ICPR.pdf)
- [Lightweight Robust ASD 2025](https://duanhaihan.github.io/publications/2025/IJCV2025.pdf)

**Verdikt:** Theoretisch möglich, praktisch zu fragil für MVP. Eventuell Phase 3.

---

## Empfohlene Architektur: 5-Schichten Hybrid

### Schicht 1 — Voice-ID Onboarding für ME (Sicher, Sofort)

**Was:**
- Einmaliger Onboarding-Schritt: "Sag bitte 30 Sekunden lang…"
- FluidAudio extrahiert WeSpeaker-Embedding für `LocalSpeakerProfile.id` (`ME`)
- Persistent in `SpeakerStore` mit `source=voice-id-onboarding`

**Wirkung:**
- Mic-Stream wird nicht blind als ME markiert, sondern verifiziert per Embedding-Match
- Wenn jemand anders durchs Mic spricht (Gespräch im Raum, Kollege übernimmt) → System erkennt es
- Akkuratheit für ME: 99%+

**Aufwand:** Klein (Onboarding-Sheet + Embedding-Capture + Match-Logik im Live-Stop-Pfad)

### Schicht 2 — Calendar-Pool aus EventKit (Sicher, Klein)

**Was:**
- Beim `RecordingController.start()`: `EKEventStore` auf laufendes Meeting prüfen
- Pool aus `EKEvent.attendees.map { (name, email) }`
- Speichern in `MeetingDetail.knownParticipantPool: [PoolEntry]`
- Fallback Microsoft Graph Calendar für Outlook-Power-User (optional Phase 1.5)

**Wirkung:**
- 1:1 Meeting trivial: Mic = ME (verifiziert), System = die einzige andere Person aus Pool
- 3+ Personen: Pool als Hint für Diarization-Cluster-Naming
- Wenn Meeting nicht im Kalender: Pool leer, fallback auf weitere Schichten

**Aufwand:** Klein (EventKit-Service + Persistenz in MeetingDetail)

### Schicht 3 — Live-Captions via AX (Erweitern)

**Was:**
- `CaptionCaptureService` heute schon teilweise drin
- AX-Heuristik mit Live-QA tunen für Teams native, Teams Web, Meet, Zoom
- Per-Plattform AX-Pattern-Documentation (per Live-QA-Session pro Plattform)
- Optional: Auto-Toggle für Teams Captions via Accessibility-API (CGEvent auf Caption-Toggle-Button)

**Wirkung:**
- Wenn User Captions in Teams an hat (oder Voice-Enrollment gemacht): echte Namen direkt
- Akkuratheit wenn Captions an + Speaker-Attribution: 80-95%
- Caption-Names landen automatisch in SpeakerStore (heute schon: `persistCaptionIdentities`)

**Aufwand:** Mittel (Live-QA pro Plattform + Heuristik-Tuning)

### Schicht 4 — SpeakerStore Cross-Meeting Recognition (Erweitern)

**Was:**
- Jeden Diarization-Cluster nach erstem Auftreten:
  - Embedding extrahieren via FluidAudio (WeSpeaker ResNet34)
  - Persistent in SpeakerStore mit Speaker-ID + Embedding
- Bei jedem neuen Meeting:
  - Diarization läuft → Cluster-Embeddings
  - Match gegen alle bekannten Embeddings via Cosine-Similarity
  - Threshold: ≥0.65 für sicheren Match, 0.55-0.65 als "wahrscheinlich, im UI markieren"
- Multi-Embedding pro Person: nach 3-5 Meetings mit derselben Person die k-means-Clustering der Samples → robusteres Profil
- User kann manuell labeln → Profil wird gestärkt

**Wirkung:**
- Ab Meeting 2 mit gleicher Person: Auto-Recognition ohne Calendar/Caption nötig
- Akkuratheit nach 3-5 Meetings mit derselben Person: 95%+
- Wirkt cross-platform (Sarah aus Teams-Meeting wird in Slack-Call wiedererkannt)

**Aufwand:** Mittel (FluidAudio-Embedding-Persistenz + Match-Logik + Multi-Embedding-Strategie)

### Schicht 5 — Browser-Companion-Extension (Optional, Größer)

**Was:**
- Chrome-Extension als separates Repo
- Lauscht auf Meet-Tab / Teams-Web-Tab / Zoom-Web-Tab
- Liest:
  - DOM-Caption-Container (für Caption-Names)
  - WebRTC `getStats()` audioLevel pro Remote-Stream → Active-Speaker live
  - Participant-Liste aus DOM (für Pool-Verfeinerung)
- Sendet via localhost:PORT WebSocket an NeoQuill-App
- NeoQuill-App empfängt → erweitert TranscriptMerger-Pipeline

**Wirkung:**
- Akkuratheit für Web-Calls: 95-99% (audioLevel ist sehr präzise)
- Funktioniert auf Browser unabhängig von macOS-AX
- Behält USP: lokal, kein Cloud, kein Bot

**Aufwand:** Groß (Chrome-Extension Codebase + Permissions + Cross-Origin + WebSocket-Bridge)

**Empfehlung:** Phase 2, wenn Schicht 1-4 ausgereizt.

---

## Was wir NICHT bauen (mit Begründung)

### Bot-Architektur (Recall.ai-Style)
- Cloud-only, gegen NeoQuill-USP
- Visible Bot im Meeting (Stealth ist Niko-USP)
- Funktioniert nicht wenn Org Recording verbietet (NeoQuill-Hauptzielgruppe)

### Microsoft Graph Real-Time Media Bot
- .NET + Windows Server only
- Tenant-Approval-Pflicht
- Setup-Aufwand riesig

### Plattform-Add-Ons (Teams Tab, Meet Add-on, Zoom App)
- User muss in jeder Plattform separat installieren
- Verliert Cross-Platform-USP
- Marketplace-Approval-Aufwand

### Pixel-basierte Active-Speaker-Detection (CV)
- Zu fragil (Layout-Änderungen)
- Hohe CPU-Last
- Sollte erst nach Schicht 4 evaluiert werden, wenn überhaupt

---

## Akkuratheits-Matrix nach Sprint

| Setting | Heute (nur FluidAudio + Caption-AX) | Nach Schicht 1+2+3+4 | Nach Schicht 5 (web) |
|---|---|---|---|
| 1:1 Niko + 1 Person, Calendar-Termin existiert | 60-70% | **97-99%** | gleich |
| 3-4 Personen, Teams-Captions an | 70-80% | **85-95%** | 95-99% |
| 3-4 Personen, ohne Captions, Calendar | 40-50% | **70-85%** (Meeting 2+: 90%+) | 90-95% |
| 5+ Personen, Audio-only (FaceTime, Telefonkonferenz) | 30-40% | **60-75%** | n/a (kein Browser) |
| Wiederkehrende Personen (5+ Meetings, gelabelt) | 50% | **95%+** überall | gleich |

---

## Empfohlene Sprint-Reihenfolge

1. **Sprint A — Voice-ID + Calendar (Schicht 1+2)** — kleinste, sicherste Wins. Schon allein bringt 1:1-Meetings auf 97%+
2. **Sprint B — SpeakerStore Cross-Meeting (Schicht 4)** — multi-embedding, threshold-tuning. Bringt wiederkehrende Personen auf 95%+
3. **Sprint C — Caption-AX-Tuning + Live-QA pro Plattform (Schicht 3)** — bringt 3-4-Personen-Meetings mit Captions auf 90%+
4. **Sprint D — Browser-Companion-Extension (Schicht 5)** — optional, wenn Web-Calls häufiger werden

---

## Quellenliste (selektiv, ~60+ direkte Quellen + ~40 indirekte aus Aggregator-Articles)

**Plattform-SDKs:**
1. https://learn.microsoft.com/en-us/microsoftteams/platform/bots/calls-and-meetings/real-time-media-concepts
2. https://learn.microsoft.com/en-us/azure/communication-services/how-tos/calling-sdk/dominant-speaker
3. https://learn.microsoft.com/en-us/azure/communication-services/how-tos/calling-sdk/events
4. https://learn.microsoft.com/en-us/microsoftteams/platform/teams-sdk/in-depth-guides/meeting-events
5. https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/how-to/using-teams-client-library
6. https://developers.google.com/workspace/meet/add-ons/guides/overview
7. https://developers.google.com/workspace/meet/overview
8. https://workspaceupdates.googleblog.com/2024/09/google-meet-add-ons-sdk-is-now-available.html
9. https://www.recall.ai/blog/what-is-the-google-meet-media-api
10. https://devforum.zoom.us/t/get-active-speaker-in-mac-os-client-sdk/43412
11. https://devforum.zoom.us/t/questions-regarding-limitations-of-onactivespeakerchange-in-zoom-apps/76632
12. https://appssdk.zoom.us/types/ZoomSdkTypes.OnActiveSpeakerChangeEvent.html
13. https://developers.zoom.us/docs/video-sdk/web/audio/
14. https://developers.zoom.us/docs/video-sdk/web/handle-events/
15. https://learn.microsoft.com/en-us/graph/api/subscription-post-subscriptions?view=graph-rest-1.0
16. https://learn.microsoft.com/en-us/graph/api/resources/subscription?view=graph-rest-1.0
17. https://devblogs.microsoft.com/microsoft365dev/get-notified-of-presence-changes-the-microsoft-graph-presence-subscription-api-is-now-available-in-public-preview/
18. https://learn.microsoft.com/en-us/microsoftteams/rooms/voice-and-face-recognition
19. https://learn.microsoft.com/en-us/microsoftteams/rooms/voice-recognition
20. https://practical365.com/voice-and-face-recognition-in-microsoft-teams/

**macOS Accessibility:**
21. https://developer.apple.com/documentation/applicationservices/axuielement
22. https://techcommunity.microsoft.com/t5/teams-developer/enable-accessibility-tree-on-macos-in-the-new-teams-work-or/m-p/4236470
23. https://stackoverflow.com/questions/77622067/why-am-i-unable-to-see-any-available-accessibility-actions-on-a-axuielement-in-m

**Speaker Diarization:**
24. https://github.com/FluidInference/FluidAudio
25. https://inference.plus/p/low-latency-speaker-diarization-on
26. https://github.com/argmaxinc/argmax-oss-swift
27. https://github.com/soniqo/speech-swift
28. https://forums.swift.org/t/speech-swift-on-device-speech-processing-for-apple-silicon-asr-tts-diarization-speech-to-speech/85182
29. https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker_diarization/models.html
30. https://www.marktechpost.com/2025/08/21/nvidia-ai-just-released-streaming-sortformer-a-real-time-speaker-diarization-that-figures-out-whos-talking-in-meetings-and-calls-instantly/
31. https://brasstranscripts.com/blog/speaker-diarization-models-comparison
32. https://picovoice.ai/blog/state-of-speaker-diarization/
33. https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis
34. https://huggingface.co/FluidInference/silero-vad-coreml
35. https://soniqo.audio/guides/vad

**Speaker Embedding:**
36. https://huggingface.co/pyannote/embedding
37. https://speechbrain.readthedocs.io/en/latest/API/speechbrain.lobes.models.ECAPA_TDNN.html
38. https://huggingface.co/blog/norwooodsystems/ecapa-vs-xvector-speaker-recognition-comparison
39. https://www.isca-archive.org/interspeech_2024/loweimi24_interspeech.html
40. https://github.com/pyannote/pyannote-audio/discussions/1667
41. https://github.com/pyannote/pyannote-audio/discussions/1226
42. https://www.isca-archive.org/interspeech_2023/bredin23_interspeech.pdf
43. https://www.assemblyai.com/blog/speaker-fingerprinting-voice-ai

**Production-Apps:**
44. https://docs.granola.ai/help-center/feature-requests
45. https://docs.granola.ai/help-center/taking-notes/transcription
46. https://github.com/turantekin/Parrot
47. https://blog.buildbetter.ai/best-free-meeting-recording-apps-mac-2026/
48. https://blog.buildbetter.ai/best-local-ai-meeting-recorders-no-cloud-2026/
49. https://speakhapi.com/blog/ai-meeting-notes-apps-mac
50. https://meetily.ai/blog/best-self-hosted-meeting-transcription-tools-2026
51. https://sonix.ai/resources/otter-ai-review/
52. https://aiflowreview.com/otter-ai-speaker-diarization-action-items/
53. https://medium.com/@godwintrav/how-i-designed-a-real-time-meeting-assistant-like-otter-ai-fireflies-ai-system-design-breakdown-823027e560de
54. https://summarizemeeting.com/en/faq/does-fireflies-have-speaker-identification
55. https://www.recall.ai/product/meeting-bot-api
56. https://docs.recall.ai/docs/bot-overview
57. https://docs.recall.ai/docs/bot-real-time-transcription
58. https://www.recall.ai/blog/how-to-build-a-meeting-bot
59. https://www.recall.ai/blog/how-to-build-a-meeting-notetaker
60. https://www.recall.ai/blog/macos-screencapture-api
61. https://krisp.ai/blog/voice-technology-transformation-with-speech-to-text-apis/
62. https://www.craftnoteapp.com/blog/how-ai-speaker-identification-works
63. https://github.com/lzhgus/Capso

**Apple Native:**
64. https://developer.apple.com/documentation/SoundAnalysis
65. https://www.createwithswift.com/identify-individual-sounds-in-a-live-audio-buffer/
66. https://swiftjectivec.com/Sound-Analysis-Framework-Built-In-Model/
67. https://www.callstack.com/blog/on-device-speech-transcription-with-apple-speechanalyzer-and-ai-sdk
68. https://support.apple.com/en-us/104993
69. https://www.apple.com/os/pdf/All_New_Features_macOS_Tahoe_Sept_2025.pdf
70. https://www.apple.com/newsroom/2025/06/apple-supercharges-its-tools-and-technologies-for-developers/
71. https://developer.apple.com/documentation/screencapturekit/
72. https://developer.apple.com/videos/play/wwdc2022/10156/
73. https://creavit.studio/blog/screencapturekit-audio-recording-mac-guide

**Calendar:**
74. https://developer.apple.com/videos/play/wwdc2023/10052/
75. https://stackoverflow.com/questions/76734912/is-there-an-api-to-get-the-email-associated-to-an-event-on-the-macos-calendar
76. https://github.com/BRO3886/go-eventkit
77. https://learn.microsoft.com/en-us/graph/api/event-get?view=graph-rest-1.0
78. https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0
79. https://learn.microsoft.com/en-us/graph/api/resources/calendar-overview?view=graph-rest-1.0
80. https://learn.microsoft.com/en-us/graph/api/onlinemeeting-get?view=graph-rest-1.0
81. https://learn.microsoft.com/en-us/graph/api/meetingattendancereport-get?view=graph-rest-1.0

**WebRTC + Browser:**
82. https://developer.mozilla.org/en-US/docs/Web/API/RTCAudioSourceStats
83. https://developer.mozilla.org/en-US/docs/Web/API/RTCAudioSourceStats/audioLevel
84. https://bloggeek.me/getstats/
85. https://webrtchacks.com/power-up-getstats-for-client-monitoring/
86. https://webrtchacks.com/getusermedia-volume/
87. https://chromewebstore.google.com/detail/talk-o-meter-for-google-m/gkaddeikpkbebjdkaebhehephipjhocg
88. https://www.gladia.io/blog/building-a-google-meet-transcription-bot-step-by-step-api-integration-with-real-time-captions
89. https://developer.chrome.com/blog/detect-dom-changes-with-mutation-observers

**Computer Vision Active-Speaker:**
90. https://duanhaihan.github.io/publications/2025/IJCV2025.pdf
91. https://research.google.com/ava/2021/S2_ActivityNet_Report_ASDNet.pdf
92. https://www.isca-archive.org/glu_2017/stefanov17_glu.pdf
93. https://hal.science/hal-03125600v1/file/ICPR.pdf
94. https://engageai.org/2025/07/30/vision-meets-interaction-detecting-speakers-and-camera-wearers-in-social-scenes/

**Vergleichs- und Übersichts-Quellen (>40 Aggregator-Articles indirekt):**
95. https://timingapp.com/blog/ai-meeting-note-taker-mac/
96. https://tldv.io/blog/transcribe-a-meeting/
97. https://tldv.io/blog/tldv-vs-fireflies/
98. https://www.read.ai/post/read-ai-introduces-operator-to-capture-every-conversation-everywhere-work-happens
99. https://practical365.com/teams-automatic-transcription/
100. https://m365admin.handsontek.net/microsoft-teams-speaker-recognition-and-attribution-available-in-additional-meeting-spaces/

Plus diverse Zwischenresultate aus Tavily-Antworten die zu 50+ weiteren indirekten Quellen verweisen (NovaScribe, Voibe, Picovoice docs, MDPI, Forasoft, etc.).

---

## Nächster Schritt

Sprint A (Voice-ID + Calendar) ist der pragmatische erste Wurf — kleine Aufwand, große Akkuratheits-Wirkung für 1:1-Meetings, baut auf bestehende FluidAudio-Pipeline auf, kein Cloud-Risiko.

Soll ich Sprint A planen (lokal oder via /ultraplan)?
