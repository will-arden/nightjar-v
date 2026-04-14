import csv
import os
import random

# Function to generate a single test vector
def rand_bits(width):
    return "".join(random.choice("01") for i in range(width))

def generate_test_vectors_csv(width, num_rows, filepath="inputs/vectors.csv"):
    print(f"Generating test vectors...")

    # Create and open a new CSV
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", newline="") as f:

        writer = csv.writer(f) # New writer object

        # Generate 
        for i in range(num_rows):
            writer.writerow([rand_bits(width)])

