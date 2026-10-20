# Python Tools

Python utilities for generating golden reference data, verifying RTL results, and converting HEX images to PNG.

---

## Files

| File | Purpose |
| --- | --- |
| `golden_model.py` | Runs the complete Python golden DSP pipeline |
| `preprocess.py` | Grayscale/image preprocessing |
| `noise.py` | Deterministic salt-and-pepper noise |
| `median.py` | 3x3 Median reference implementation |
| `sobel.py` | Sobel, gradient magnitude, threshold reference |
| `verify.py` | Compares expected HEX with RTL/C output |
| `hex2img.py` | Converts ASCII HEX image data to PNG |

---

## 1. Activate the Virtual Environment

From the repository root:

```powershell
.\.venv\Scripts\Activate.ps1
```

If PowerShell blocks activation:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\.venv\Scripts\Activate.ps1
```

Install dependencies:

```powershell
python -m pip install numpy pillow
```

Then enter:

```powershell
cd .\python\
```

Expected prompt:

```text
(.venv) PS D:\FPGA_Project\image_dsp\image-dsp-benchmark\python>
```

---

## 2. Run the Golden Model

Default:

```powershell
python golden_model.py
```

64x64:

```powershell
python golden_model.py --width 64 --height 64
```

128x128:

```powershell
python golden_model.py --width 128 --height 128
```

256x256:

```powershell
python golden_model.py --width 256 --height 256
```

512x512:

```powershell
python golden_model.py --width 512 --height 512
```

640x480:

```powershell
python golden_model.py --width 640 --height 480
```

1024x1024:

```powershell
python golden_model.py --width 1024 --height 1024
```

Typical generated files:

```text
gray.hex
noisy.hex
median.hex
gradient.hex
expected.hex
```

---

## 3. Verify RTL Output

Example for 64x64:

```powershell
python verify.py --expected ..\results\64x64\expected.hex --actual ..\results\64x64\rtl_result.hex
```

512x512:

```powershell
python verify.py --expected ..\results\512x512\expected.hex --actual ..\results\512x512\rtl_result.hex
```

640x480:

```powershell
python verify.py --expected ..\results\640x480\expected.hex --actual ..\results\640x480\rtl_result.hex
```

Required result:

```text
mismatch = 0
PASS
```

---

## 4. Convert HEX to PNG

64x64 RTL output:

```powershell
python hex2img.py ..\results\64x64\rtl_result.hex --width 64 --height 64
```

64x64 expected output:

```powershell
python hex2img.py ..\results\64x64\expected.hex --width 64 --height 64
```

512x512:

```powershell
python hex2img.py ..\results\512x512\rtl_result.hex --width 512 --height 512
python hex2img.py ..\results\512x512\expected.hex --width 512 --height 512
```

640x480:

```powershell
python hex2img.py ..\results\640x480\rtl_result.hex --width 640 --height 480
python hex2img.py ..\results\640x480\expected.hex --width 640 --height 480
```

The PNG is saved in the same directory as the input HEX.

Example:

```text
results/
└── 64x64/
    ├── expected.hex
    ├── expected.png
    ├── rtl_result.hex
    └── rtl_result.png
```

---

## 5. Check HEX Length

64x64:

```powershell
(Get-Content ..\results\64x64\rtl_result.hex).Count
```

Expected:

```text
4096
```

512x512:

```powershell
(Get-Content ..\results\512x512\rtl_result.hex).Count
```

Expected:

```text
262144
```

640x480:

```powershell
(Get-Content ..\results\640x480\rtl_result.hex).Count
```

Expected:

```text
307200
```

---

## Typical Workflow

```text
golden_model.py
      |
      v
expected.hex
      |
      +---------------------+
      |                     |
      v                     v
RTL Simulation          hex2img.py
      |                     |
      v                     v
rtl_result.hex       expected.png
      |
      v
verify.py
      |
      v
Python == RTL
mismatch = 0
PASS
```

Example 64x64 flow:

```powershell
python golden_model.py --width 64 --height 64

# Run Vivado/XSim and generate:
# ..\results\64x64\rtl_result.hex

python verify.py --expected ..\results\64x64\expected.hex --actual ..\results\64x64\rtl_result.hex

python hex2img.py ..\results\64x64\expected.hex --width 64 --height 64
python hex2img.py ..\results\64x64\rtl_result.hex --width 64 --height 64
```
