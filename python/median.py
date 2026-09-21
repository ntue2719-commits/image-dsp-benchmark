import numpy as np

def median_filter_3x3(img_noisy):
    H, W = img_noisy.shape
    median_out = np.zeros((H, W), dtype=np.uint8)
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            window = img_noisy[y-1:y+2, x-1:x+2]
            median_val = np.median(window)
            median_out[y, x] = int(median_val)
    return median_out

