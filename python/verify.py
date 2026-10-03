import sys

def verify_files(expected_file, rtl_file):
    print(f"Verifying {rtl_file} against {expected_file}...")
    try:
        with open(expected_file, 'r') as f1, open(rtl_file, 'r') as f2:
            expected_lines = f1.readlines()
            rtl_lines = f2.readlines()
            
        if len(expected_lines) != len(rtl_lines):
            print("ERROR: File lengths do not match!")
            return False
            
        mismatches = 0
        for i, (exp, rtl) in enumerate(zip(expected_lines, rtl_lines)):
            if exp.strip() != rtl.strip():
                if mismatches < 10:
                    print(f"Mismatch at index {i}: expected {exp.strip()}, got {rtl.strip()}")
                mismatches += 1
                
        if mismatches == 0:
            print("SUCCESS: 0 Mismatches! RTL matches Golden Model perfectly.")
            return True
        else:
            print(f"FAILED: Found {mismatches} mismatches total.")
            return False
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python verify.py <expected.hex> <rtl_output.hex>")
    else:
        verify_files(sys.argv[1], sys.argv[2])
