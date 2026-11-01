from __future__ import annotations
import os
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename

from bench_core import run_benchmark


def create_app(board: str, base_dir: Path, with_fpga: bool):
    app = Flask(__name__, template_folder=str(base_dir.parent / 'templates'))
    results_root = base_dir / 'results'
    uploads = base_dir / 'uploads'
    results_root.mkdir(exist_ok=True)
    uploads.mkdir(exist_ok=True)

    cpu_bin = Path(os.getenv('CPU_DSP_BIN', str(base_dir / 'cpu_dsp')))
    fpga_main = Path(os.getenv('FPGA_MAIN', '/home/ubuntu/TueNT/image_dsp/main')) if with_fpga else None
    fpga_sudo = os.getenv('FPGA_SUDO', '1') != '0'
    width = int(os.getenv('IMAGE_WIDTH', '64'))
    height = int(os.getenv('IMAGE_HEIGHT', '64'))
    threshold = int(os.getenv('THRESHOLD', '100'))

    @app.get('/')
    def index():
        return render_template('index.html', board=board, result=None)

    @app.post('/benchmark')
    def benchmark():
        f = request.files.get('file')
        if not f or not f.filename:
            return 'missing file', 400
        name = secure_filename(f.filename) or 'input.hex'
        path = uploads / name
        f.save(path)
        try:
            result, work = run_benchmark(board, path, results_root, cpu_bin, width, height, threshold, fpga_main, fpga_sudo)
        except Exception as e:
            return f'<h1>Benchmark failed</h1><pre>{e}</pre><p><a href="/">Back</a></p>', 500
        return render_template('index.html', board=board, result=result, result_dir=str(work))

    @app.get('/api/health')
    def health():
        return jsonify({'ok': True, 'board': board, 'fpga': with_fpga, 'cpu_bin': str(cpu_bin), 'fpga_main': str(fpga_main) if fpga_main else None})

    @app.get('/results/<stamp>/<path:name>')
    def results(stamp, name):
        return send_from_directory(results_root / stamp, name, as_attachment=True)

    return app
