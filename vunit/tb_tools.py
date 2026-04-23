import os
import csv
import random

# Function to generate a single test vector
def rand_bits(width):
    return "".join(random.choice("01") for i in range(width))

# Function to convert a binary string to a hexadecimal string
def bin_to_hex(bits, case="upper"):
    num_value = int(bits, 2)
    num_hex_chars = (len(bits) + 3) // 4
    if (case == "upper"):
        return f"{num_value:0{num_hex_chars}X}"
    elif (case == "lower"):
        return f"{num_value:0{num_hex_chars}x}"
    else:
        raise Exception(f"Invalid case ""{case}""; should be ""upper"" or ""lower"".")

# Function to generate a CSV filled with random data
def generate_test_vectors_csv(width, num_rows, filepath="inputs/vectors.csv"):
    print(f"Generating test vectors...")

    # Create and open a new CSV
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", newline="") as f:

        writer = csv.writer(f) # New writer object

        # Generate 
        for i in range(num_rows):
            # random_row = bin_to_hex(rand_bits(width))
            random_row = rand_bits(width)
            writer.writerow([random_row])

