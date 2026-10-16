#!/usr/bin/env python3
"""hex2img.py - Khoi phuc anh tu file hex.

Cach dung:
    python hex2img.py data.hex
    python hex2img.py data.hex -o out.png
    python hex2img.py data.hex --width 128 --height 64
    python hex2img.py data.hex --channels 3 --width 100
    python hex2img.py data.hex --invert
    python hex2img.py ..\results\640x480\rtl_result.hex --width 640 --height 480 
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def read_hex(path):
    data = []

    with open(path, "r", errors="ignore") as f:
        for line in f:

            # Bo comment
            line = line.split("//")[0].split("#")[0].strip()

            # Bo dong rong / dia chi $readmemh
            if not line or line.startswith("@"):
                continue

            for tok in line.replace(",", " ").split():

                tok = tok.lower().replace("0x", "")

                # Token le -> them 0 phia truoc
                if len(tok) % 2:
                    tok = "0" + tok

                # Token dai -> tach tung byte
                for i in range(0, len(tok), 2):
                    data.append(
                        int(tok[i:i + 2], 16)
                    )

    return np.array(data, dtype=np.uint8)


def row_score(arr, w, ch):
    """
    Do 'muot' theo chieu doc.
    Score nho -> cac hang co xu huong giong nhau hon.
    """

    h = len(arr) // (w * ch)

    if h < 8:
        return None

    img = arr[:h * w * ch].reshape(
        h,
        w * ch
    ).astype(np.int16)

    return np.abs(
        img[1:] - img[:-1]
    ).mean()


def guess_size(arr, ch, top=5):

    n = len(arr) // ch

    cands = []

    for w in range(
        8,
        min(4096, n // 8) + 1
    ):

        s = row_score(
            arr,
            w,
            ch
        )

        if s is not None:
            cands.append(
                (
                    s,
                    w,
                    n // w
                )
            )

    cands.sort()

    return cands[:top]


def main():

    ap = argparse.ArgumentParser()

    ap.add_argument(
        "hexfile"
    )

    ap.add_argument(
        "-o",
        "--output",
        default=None,
        help="Ten file output. Neu chi ghi ten file, anh se duoc luu cung thu muc voi file HEX."
    )

    ap.add_argument(
        "--width",
        type=int
    )

    ap.add_argument(
        "--height",
        type=int
    )

    ap.add_argument(
        "--channels",
        type=int,
        default=1,
        choices=[1, 3, 4]
    )

    ap.add_argument(
        "--invert",
        action="store_true"
    )

    args = ap.parse_args()


    # ============================================================
    # Input path
    # ============================================================

    hex_path = Path(args.hexfile)

    if not hex_path.exists():
        raise FileNotFoundError(
            f"Khong tim thay file HEX: {hex_path}"
        )


    # ============================================================
    # Output path
    # ============================================================

    if args.output is None:

        # Khong truyen -o:
        #
        # rtl_result.hex
        # ->
        # rtl_result.png

        output_path = hex_path.with_suffix(".png")

    else:

        user_output = Path(args.output)

        # Neu user chi ghi:
        #
        # -o rtl_result.png
        #
        # thi luu cung folder voi HEX.

        if user_output.parent == Path("."):

            output_path = (
                hex_path.parent /
                user_output.name
            )

        else:

            # Neu user truyen full/relative path
            # thi dung dung path do.

            output_path = user_output


    # ============================================================
    # Read HEX
    # ============================================================

    arr = read_hex(hex_path)

    ch = args.channels

    print(
        f"Doc duoc {len(arr)} byte"
    )


    # ============================================================
    # Resolve image size
    # ============================================================

    if args.width:

        w = args.width

        h = (
            args.height
            or len(arr) // (w * ch)
        )

    else:

        cands = guess_size(
            arr,
            ch
        )

        if not cands:
            raise RuntimeError(
                "Khong the tu dong doan kich thuoc anh."
            )

        print(
            "Cac kich thuoc kha di "
            "(score cang nho cang tot):"
        )

        for s, cw, chh in cands:

            print(
                f"  {cw} x {chh}   "
                f"score={s:.2f}"
            )

        _, w, h = cands[0]

        print(
            f"=> Chon {w} x {h}"
        )


    # ============================================================
    # Validate / pad
    # ============================================================

    need = w * h * ch

    if len(arr) < need:

        print(
            f"Can {need} byte nhung "
            f"chi co {len(arr)} byte."
        )

        print(
            "Phan thieu se duoc chen 0."
        )

        arr = np.pad(
            arr,
            (0, need - len(arr))
        )

    elif len(arr) > need:

        print(
            f"Can {need} byte, "
            f"file co {len(arr)} byte."
        )

        print(
            "Phan du se bi bo qua."
        )


    # ============================================================
    # Reshape
    # ============================================================

    if ch == 1:

        img = arr[:need].reshape(
            h,
            w
        )

    else:

        img = arr[:need].reshape(
            h,
            w,
            ch
        )


    # ============================================================
    # Optional invert
    # ============================================================

    if args.invert:

        img = 255 - img


    # ============================================================
    # Save image
    # ============================================================

    mode = {
        1: "L",
        3: "RGB",
        4: "RGBA"
    }[ch]

    # Tao folder neu chua ton tai
    output_path.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    Image.fromarray(
        img,
        mode
    ).save(
        output_path
    )


    print(
        f"Da luu: {output_path}"
    )


if __name__ == "__main__":
    main()