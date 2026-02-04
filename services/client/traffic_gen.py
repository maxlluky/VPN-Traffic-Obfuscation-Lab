#!/usr/bin/env python3
import argparse
import time
import random
import requests
import sys

def setup_args():
    parser = argparse.ArgumentParser(description="VPN Lab Traffic Generator")
    parser.add_argument("--target", required=True, help="Target Base URL (e.g. http://1.2.3.4:80)")
    parser.add_argument("--count", type=int, default=50, help="Number of requests")
    parser.add_argument("--seed", type=str, default=None, help="Random seed for reproducibility")
    parser.add_argument("--delay-min", type=float, default=0.1, help="Min delay between requests (sec)")
    parser.add_argument("--delay-max", type=float, default=2.0, help="Max delay between requests (sec)")
    return parser.parse_args()

def main():
    args = setup_args()
    
    # Initialize Randomness
    if args.seed:
        print(f"[*] Use Seed: {args.seed}", flush=True)
        random.seed(args.seed)
    else:
        # Generate a random seed if none provided and print it
        new_seed = str(random.randint(0, 999999))
        print(f"[*] Generated Seed: {new_seed}", flush=True)
        random.seed(new_seed)

    # Define Assets and Weights
    # Weights roughly simulate: many small page loads, fewer large downloads
    paths = [
        "/", 
        "/index.html",
        "/data/50KB.bin",
        "/data/200KB.bin",
        "/data/1MB.bin"
    ]
    weights = [40, 30, 20, 8, 2] # Sum doesn't need to be 100, random.choices handles it
    
    s = requests.Session()
    success_count = 0
    fail_count = 0

    print(f"[*] Starting {args.count} requests to {args.target}...", flush=True)

    for i in range(args.count):
        # Pick a path
        path = random.choices(paths, weights=weights, k=1)[0]
        url = f"{args.target}{path}"
        
        # Request
        try:
            # Random User-Agent for variety (optional, keep simple for now)
            # headers = {'User-Agent': f'VPNLabClient/{i}'}
            resp = s.get(url, timeout=5)
            status = resp.status_code
            size = len(resp.content)
            print(f"[{i+1}/{args.count}] GET {path} -> {status} ({size} bytes)", flush=True)
            
            if status == 200:
                success_count += 1
            else:
                fail_count += 1
                
        except Exception as e:
            print(f"[!] Error requesting {url}: {e}", flush=True)
            fail_count += 1

        # Think time (except after last request)
        if i < args.count - 1:
            delay = random.uniform(args.delay_min, args.delay_max)
            time.sleep(delay)

    print(f"\n[*] Finished. Success: {success_count}, Fail: {fail_count}", flush=True)
    if fail_count > args.count * 0.2: # Fail if >20% failure
        sys.exit(1)

if __name__ == "__main__":
    main()
