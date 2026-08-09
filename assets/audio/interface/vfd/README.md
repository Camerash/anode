# VFD Button Actuation Audio

Source file: `thepixelguymaker-button-click-vintage-sound-fx-541135.mp3`

The source recording is not included in the app bundle. The project owner
provided it for this use and confirmed redistribution rights for the derived
samples.

Both assets are mono, 48 kHz, 16-bit PCM WAV files. Their relative levels are
unchanged.

- `button_down.wav`: source 24-90 ms, 2 ms fade-in, 6 ms fade-out.
- `button_up.wav`: source 106-220 ms, 2 ms fade-in, 7 ms fade-out.

Generation commands:

```bash
ffmpeg -i source.mp3 -af "atrim=start=0.024:end=0.090,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.002,afade=t=out:st=0.060:d=0.006" -ac 1 -ar 48000 -c:a pcm_s16le button_down.wav
ffmpeg -i source.mp3 -af "atrim=start=0.106:end=0.220,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.002,afade=t=out:st=0.107:d=0.007" -ac 1 -ar 48000 -c:a pcm_s16le button_up.wav
```
