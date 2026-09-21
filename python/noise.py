import numpy as np

def add_salt_and_pepper_noise(img_gray, noise_prob=0.05, seed=12345):
    np.random.seed(seed)
    noisy = np.copy(img_gray)
    H, W = noisy.shape
    rand_mat = np.random.rand(H, W)
    noisy[rand_mat < (noise_prob / 2.0)] = 0
    noisy[(rand_mat >= (noise_prob / 2.0)) & (rand_mat < noise_prob)] = 255
    return noisy
