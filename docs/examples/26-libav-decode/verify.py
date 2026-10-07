from __future__ import annotations
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

MEDIA = str(Path(__file__).resolve().parent / '.build/media')
passed: list[str] = []

def command(args: list[str], expected: int = 0, seconds: int = 30) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(args, capture_output=True, timeout=seconds, env={**os.environ, 'TZ': 'UTC'})
    assert result.returncode == expected, (args, result.returncode, result.stdout[-1500:], result.stderr[-2500:])
    return result

def probe(path: Path, entries: str, packets: bool = False) -> dict[str, object]:
    args = ['/usr/bin/ffprobe', '-v', 'error', '-count_frames', '-show_entries', entries, '-of', 'json']
    if packets:
        args.append('-show_packets')
    data: object = json.loads(command(args + [str(path)]).stdout)
    assert isinstance(data, dict)
    return data

def stream_rows(path: Path) -> list[dict[str, str]]:
    data = probe(path, 'stream=codec_name,codec_type,nb_read_frames,time_base')
    rows = data.get('streams')
    assert isinstance(rows, list)
    checked: list[dict[str, str]] = []
    for row in rows:
        assert isinstance(row, dict)
        assert all(isinstance(key, str) and isinstance(value, str) for key, value in row.items())
        checked.append(row)
    return checked

def metrics(result: subprocess.CompletedProcess[bytes]) -> dict[str, int]:
    pairs = re.findall(rb'(packets|frames|audio_samples|streams)=(\d+)', result.stdout)
    assert len(pairs) == 4, result.stdout
    return {key.decode(): int(value) for key, value in pairs}

def rejects(args: list[str], status: int = 1) -> subprocess.CompletedProcess[bytes]:
    result = command([MEDIA] + args, expected=status)
    assert result.stdout == b'', result.stdout
    return result

with tempfile.TemporaryDirectory(prefix='odin-native-media-') as directory:
    root = Path(directory)
    audio = root / 'audio sample.wav'
    mixed = root / 'audio video.mkv'
    video = root / 'reordered.mp4'
    command(['/usr/bin/ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
             'sine=frequency=440:sample_rate=48000', '-t', '1', str(audio)])
    command(['/usr/bin/ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
             'testsrc2=size=64x48:rate=25', '-f', 'lavfi', '-i',
             'sine=frequency=440:sample_rate=48000', '-t', '1', '-c:v', 'mpeg4', '-bf', '2',
             '-c:a', 'pcm_s16le', str(mixed)])
    command(['/usr/bin/ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
             'testsrc2=size=64x48:rate=25', '-t', '1', '-c:v', 'mpeg4', '-bf', '2', str(video)])
    for source in [audio, mixed, video]:
        result = metrics(command([MEDIA, 'decode', str(source)]))
        rows = stream_rows(source)
        assert result['streams'] == len(rows)
        assert result['frames'] == sum(int(row['nb_read_frames']) for row in rows)
        if source != video:
            assert result['audio_samples'] == 48000
        passed.append('decoded frame/sample counts match ffprobe: ' + source.suffix)
    rejects(['decode', str(root / 'missing.wav')]); passed.append('missing file')
    corrupt = root / 'corrupt.bin'; corrupt.write_bytes(b'not a media container')
    rejects(['decode', str(corrupt)]); passed.append('corrupt file')
    rejects(['decode', str(mixed), '1']); passed.append('frame budget and no partial success stdout')
    rejects(['decode', 'https://example.invalid/file'], 2); passed.append('network URL rejected before foreign call')
    rejects(['decode', 'relative.wav'], 2); passed.append('relative path rejected')
    link = root / 'linked.wav'; link.symlink_to(audio)
    rejects(['decode', str(link)]); passed.append('final-component symlink rejected')
    playlist = root / 'network.m3u8'
    playlist.write_text('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1.0\nhttp://127.0.0.1:9/disallowed.ts\n#EXT-X-ENDLIST\n')
    blocked = rejects(['decode', str(playlist)])
    assert b'not on whitelist' in blocked.stderr, blocked.stderr
    passed.append('nested HTTP protocol blocked by file whitelist')
    for source in [mixed, video]:
        output = root / ('copied-' + source.suffix[1:] + '.part')
        result = metrics(command([MEDIA, 'remux', str(source), str(output)]))
        before = stream_rows(source); after = stream_rows(output)
        assert [(r['codec_type'],r['codec_name']) for r in before] == [(r['codec_type'],r['codec_name']) for r in after]
        assert result['streams'] == len(before) and result['packets'] > 0
        assert metrics(command([MEDIA, 'decode', str(output)]))['frames'] == sum(int(r['nb_read_frames']) for r in before)
        if source == video:
            assert before[0]['time_base'] != after[0]['time_base']
            left = probe(source, 'packet=pts_time,dts_time,duration_time', packets=True).get('packets')
            right = probe(output, 'packet=pts_time,dts_time,duration_time', packets=True).get('packets')
            assert isinstance(left, list) and isinstance(right, list) and len(left) == len(right)
            for a,b in zip(left,right):
                assert isinstance(a,dict) and isinstance(b,dict)
                for key in ['pts_time','dts_time','duration_time']:
                    if key in a and key in b:
                        assert abs(float(a[key])-float(b[key])) <= .0011, (a,b)
        passed.append('remux stream/frame/timestamp contract: ' + source.suffix)
        prior = output.read_bytes()
        rejects(['remux', str(source), str(output)])
        assert output.read_bytes() == prior
        passed.append('existing output is not overwritten: ' + source.suffix)
    for mode in ['decode', 'remux']:
        log = root / ('valgrind-' + mode + '.log')
        args = ['valgrind', '--leak-check=full', '--errors-for-leak-kinds=definite', '--error-exitcode=99',
                '--log-file=' + str(log), MEDIA, mode, str(audio)]
        if mode == 'remux': args.append(str(root / 'valgrind.part'))
        command(args, seconds=60)
        text = log.read_text()
        assert 'ERROR SUMMARY: 0 errors' in text, text[-3000:]
        passed.append('Valgrind no reported errors/definite leaks: ' + mode)

print(json.dumps({'scenarios_passed': len(passed), 'checks': passed}, indent=2))
