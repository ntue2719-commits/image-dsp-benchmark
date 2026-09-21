import numpy as np

def sobel_and_threshold(img_median, threshold_val=100):
    H, W = img_median.shape
    out_img = np.zeros((H, W), dtype=np.uint8)
    mag_img = np.zeros((H, W), dtype=np.uint16)
    img = img_median.astype(np.int32)
    for y in range(2, H - 2):
        for x in range(2, W - 2):
            p00 = img[y-1, x-1]; p01 = img[y-1, x]; p02 = img[y-1, x+1]
            p10 = img[y,   x-1];                    p12 = img[y,   x+1]
            p20 = img[y+1, x-1]; p21 = img[y+1, x]; p22 = img[y+1, x+1]
            
            gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22
            gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22
            magnitude = abs(gx) + abs(gy)
            mag_img[y, x] = magnitude
            
            if magnitude >= threshold_val:
                out_img[y, x] = 255
            else:
                out_img[y, x] = 0
    return mag_img, out_img
