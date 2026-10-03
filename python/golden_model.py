
import os
import argparse
import cv2
import numpy as np

from preprocess import rgb_to_grayscale_approx
from noise import add_salt_and_pepper_noise
from median import median_filter_3x3
from sobel import sobel_and_threshold


def save_as_hex(img_array, filename, hex_width=2):
    with open(filename, 'w') as f:
        for val in img_array.flatten():
            if hex_width == 2:
                f.write(f"{int(val):02x}\n")
            else:
                f.write(f"{int(val):04x}\n")


def parse_args():
    parser = argparse.ArgumentParser(
        description="DSP Image Processing Golden Model"
    )

    parser.add_argument(
        "--width",
        type=int,
        default=512,
        help="Image width (default: 512)"
    )

    parser.add_argument(
        "--height",
        type=int,
        default=512,
        help="Image height (default: 512)"
    )

    return parser.parse_args()


def main():
    args = parse_args()

    WIDTH = args.width
    HEIGHT = args.height

    if WIDTH < 5 or HEIGHT < 5:
        raise ValueError(
            "WIDTH and HEIGHT must be >= 5 because the pipeline "
            "contains Median 3x3 followed by Sobel 3x3."
        )

    print("=== DSP Image Processing Golden Model ===")
    print(f"Target Resolution: {WIDTH}x{HEIGHT}")

    img_path = None

    if os.path.exists("input.png"):
        img_path = "input.png"
    elif os.path.exists("input.jpg"):
        img_path = "input.jpg"

    if img_path:
        print(f"Reading image from {img_path}...")

        img_bgr = cv2.imread(img_path)

        if img_bgr is None:
            raise RuntimeError(f"Failed to read image: {img_path}")

        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        img_rgb = cv2.resize(
            img_rgb,
            (WIDTH, HEIGHT),
            interpolation=cv2.INTER_LINEAR
        )

    else:
        print("Generating synthetic RGB test image...")

        img_rgb = np.zeros(
            (HEIGHT, WIDTH, 3),
            dtype=np.uint8
        )

        for y in range(HEIGHT):
            for x in range(WIDTH):
                img_rgb[y, x, 0] = x % 256
                img_rgb[y, x, 1] = y % 256
                img_rgb[y, x, 2] = (x + y) % 256

    print("1. Running RGB to Grayscale...")
    img_gray = rgb_to_grayscale_approx(img_rgb)

    save_as_hex(img_gray, "gray.hex")
    cv2.imwrite("debug_gray.png", img_gray)

    print("2. Adding Salt-and-Pepper Noise...")
    img_noisy = add_salt_and_pepper_noise(
        img_gray,
        noise_prob=0.05,
        seed=12345
    )

    save_as_hex(img_noisy, "noisy.hex")
    cv2.imwrite("debug_noisy.png", img_noisy)

    print("3. Running Median Filter 3x3...")
    img_median = median_filter_3x3(img_noisy)

    save_as_hex(img_median, "median.hex")
    cv2.imwrite("debug_median.png", img_median)

    print("4. Running Sobel & Threshold...")
    img_mag, img_out = sobel_and_threshold(
        img_median,
        threshold_val=100
    )

    save_as_hex(
        img_mag,
        "gradient.hex",
        hex_width=4
    )

    img_mag_visual = np.clip(
        img_mag / 8,
        0,
        255
    ).astype(np.uint8)

    cv2.imwrite(
        "debug_gradient.png",
        img_mag_visual
    )

    save_as_hex(
        img_out,
        "expected.hex"
    )

    cv2.imwrite(
        "debug_expected.png",
        img_out
    )

    total_pixels = WIDTH * HEIGHT
    valid_pixels = max(0, WIDTH - 4) * max(0, HEIGHT - 4)

    print("\n[SUCCESS] Generated Golden files:")
    print(f"  Resolution        : {WIDTH}x{HEIGHT}")
    print(f"  Total pixels      : {total_pixels}")
    print(f"  Valid DSP outputs : {valid_pixels}")
    print("  - noisy.hex")
    print("  - expected.hex")
    print("  - gradient.hex")
    print("  - median.hex")
    print("  - gray.hex")
    print("  - debug_*.png")


if __name__ == "__main__":
    main()