import numpy as np

def rgb_to_grayscale_approx(img_rgb):
    img_rgb = img_rgb.astype(np.uint32)
    R = img_rgb[:, :, 0]
    G = img_rgb[:, :, 1]
    B = img_rgb[:, :, 2]
    Y = (77 * R + 150 * G + 29 * B) // 256
    return Y.astype(np.uint8)
