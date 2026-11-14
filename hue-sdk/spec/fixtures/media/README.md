# Media fixtures

A two-second HLS clip in fragmented MP4, with a video and an audio track and two segments, made once with ffmpeg:

```sh
ffmpeg -f lavfi -i testsrc=duration=2:size=64x48:rate=10 -f lavfi -i sine=frequency=440:duration=2 \
  -c:v libx264 -g 10 -pix_fmt yuv420p -c:a aac -b:a 32k -shortest \
  -f hls -hls_segment_type fmp4 -hls_time 1 -hls_playlist_type vod \
  -hls_fmp4_init_filename init.mp4 -hls_segment_filename 'segment%d.m4s' clip.m3u8
```

A one-second MP4 file with the same two tracks, its moov first as the app expects of a clip from Kinesis Video's
GetClip; its chunks hold several samples, where the app expects one:

```sh
ffmpeg -f lavfi -i testsrc=duration=1:size=64x48:rate=10 -f lavfi -i sine=frequency=440:duration=1 \
  -c:v libx264 -g 10 -pix_fmt yuv420p -c:a aac -b:a 32k -shortest -movflags +faststart clip.mp4
```
