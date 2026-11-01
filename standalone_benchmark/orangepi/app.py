from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'common'))

from webapp import create_app

app = create_app('Orange Pi', Path(__file__).resolve().parent, with_fpga=False)

if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    app.run(host='0.0.0.0', port=port, threaded=False)
