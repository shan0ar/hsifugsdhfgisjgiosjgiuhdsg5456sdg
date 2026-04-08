#!/usr/bin/env python3

import itertools
import sys
import re

class WordlistGenerator:
    
    LEET_MAP = {
        'a': ['@', '4'],
        'e': ['3'],
        'i': ['!', '1'],
        'o': ['0'],
        's': ['$', '5'],
        't': ['7'],
        'l': ['1'],
        'g': ['9'],
        'z': ['2'],
        'b': ['8'],
    }
    
    SPECIAL_CHARS = ['*', '/', '-', '_', '(', ')', "'", '"', '.', ',', '+']
    
    CAPITALIZE_STYLES = [
        'word1_upper_word2_lower',
        'word1_upper_word2_first',
        'word1_upper_word2_upper',
        'word1_lower_word2_lower',
        'word1_lower_word2_first',
        'word1_lower_word2_upper',
        'word1_first_word2_first',
        'word1_first_word2_upper',
        'word1_first_word2_lower',
    ]
    
    SEPARATORS = [
        ('', ''),
        ('-', ''),
        ('-', '-'),
        ('', '-'),
        ('_', ''),
        ('_', '_'),
        ('', '_'),
        ('-', '_'),
        ('_', '-'),
    ]
    
    PRIORITY_YEARS = list(range(1960, 2027))
    
    def __init__(self, keywords: list, max_number: int = 2030):
        self.keywords = [kw.lower() for kw in keywords]
        self.max_number = max_number
        self.total_entries = 0
        self.priority_entries = []
        self.regular_entries = []
    
    def generate_combinations(self):
        for r in range(1, len(self.keywords) + 1):
            for combo in itertools.permutations(self.keywords, r):
                yield combo
    
    def apply_capitalization(self, word_tuple: tuple, style: str) -> tuple:
        if len(word_tuple) == 1:
            word = word_tuple[0]
            
            if style in ['word1_upper_word2_lower', 'word1_upper_word2_first', 'word1_upper_word2_upper']:
                return (word.upper(), '', '')
            elif style in ['word1_lower_word2_lower', 'word1_lower_word2_first', 'word1_lower_word2_upper']:
                return (word.lower(), '', '')
            elif style in ['word1_first_word2_first', 'word1_first_word2_upper', 'word1_first_word2_lower']:
                return (word[0].upper() + word[1:].lower(), '', '')
        
        if len(word_tuple) >= 2:
            word1 = word_tuple[0]
            word2 = word_tuple[1]
            rest = ''.join(word_tuple[2:])
            
            if style == 'word1_upper_word2_lower':
                return (word1.upper(), word2.lower(), rest.lower())
            elif style == 'word1_upper_word2_first':
                return (word1.upper(), word2[0].upper() + word2[1:].lower(), rest.lower())
            elif style == 'word1_upper_word2_upper':
                return (word1.upper(), word2.upper(), rest.upper())
            elif style == 'word1_lower_word2_lower':
                return (word1.lower(), word2.lower(), rest.lower())
            elif style == 'word1_lower_word2_first':
                return (word1.lower(), word2[0].upper() + word2[1:].lower(), rest.lower())
            elif style == 'word1_lower_word2_upper':
                return (word1.lower(), word2.upper(), rest.upper())
            elif style == 'word1_first_word2_first':
                return (word1[0].upper() + word1[1:].lower(), word2[0].upper() + word2[1:].lower(), rest.lower())
            elif style == 'word1_first_word2_upper':
                return (word1[0].upper() + word1[1:].lower(), word2.upper(), rest.upper())
            elif style == 'word1_first_word2_lower':
                return (word1[0].upper() + word1[1:].lower(), word2.lower(), rest.lower())
        
        return (''.join(word_tuple).lower(), '', '')
    
    def generate_leet_variations(self, word: str) -> list:
        variations = [word]
        
        positions_with_leet = []
        for i, char in enumerate(word):
            if char.lower() in self.LEET_MAP:
                positions_with_leet.append((i, char.lower()))
        
        if not positions_with_leet:
            return variations
        
        from itertools import product
        
        leet_options = []
        for pos, char in positions_with_leet:
            leet_options.append([(pos, char, original) for original in self.LEET_MAP[char]])
        
        for combo in product(*leet_options):
            variant = list(word)
            for pos, char, leet_char in combo:
                variant[pos] = leet_char
            variations.append(''.join(variant))
        
        return variations
    
    def is_priority_year(self, number: int) -> bool:
        return number in self.PRIORITY_YEARS
    
    def generate_wordlist_stream(self):
        samples = []
        
        for word_tuple in self.generate_combinations():
            for number in range(self.max_number + 1):
                for cap_style in self.CAPITALIZE_STYLES:
                    word1, word2, rest = self.apply_capitalization(word_tuple, cap_style)
                    
                    for sep_word, sep_number in self.SEPARATORS:
                        if word2:
                            base_word = f"{word1}{sep_word}{word2}{rest}"
                        else:
                            base_word = word1
                        
                        leet_variations = self.generate_leet_variations(base_word)
                        
                        for leet_variant in leet_variations:
                            entry_no_special = f"{leet_variant}{sep_number}{number}"
                            
                            if self.is_priority_year(number):
                                self.priority_entries.append((number, entry_no_special))
                            else:
                                self.regular_entries.append(entry_no_special)
                            
                            self.total_entries += 1
                            
                            if len(samples) < 100:
                                samples.append(entry_no_special)
                            
                            for special_char in self.SPECIAL_CHARS:
                                entry = f"{leet_variant}{sep_number}{number}{special_char}"
                                
                                if self.is_priority_year(number):
                                    self.priority_entries.append((number, entry))
                                else:
                                    self.regular_entries.append(entry)
                                
                                self.total_entries += 1
                                
                                if len(samples) < 100:
                                    samples.append(entry)
        
        return samples
    
    def save_to_file(self, filename: str) -> None:
        print(f"[*] Génération et sauvegarde de la wordlist...")
        print(f"[*] Cela peut prendre plusieurs minutes...")
        
        try:
            print(f"\n[*] Étape 1: Génération de toutes les entrées...")
            samples = self.generate_wordlist_stream()
            
            print(f"[+] {self.total_entries} entrées générées")
            print(f"[*] Étape 2: Tri des années prioritaires (1960-2026)...")
            
            self.priority_entries.sort(key=lambda x: (-x[0], x[1]))
            
            print(f"[+] {len(self.priority_entries)} entrées avec années prioritaires")
            print(f"[+] {len(self.regular_entries)} entrées régulières")
            
            print(f"\n[*] Étape 3: Sauvegarde dans {filename}...")
            
            with open(filename, 'w', encoding='utf-8') as f:
                for number, entry in self.priority_entries:
                    f.write(entry + '\n')
                
                for entry in self.regular_entries:
                    f.write(entry + '\n')
            
            print(f"\n[+] Wordlist sauvegardée avec succès: {filename}")
            print(f"[+] Nombre total de mots: {self.total_entries}")
            print(f"[+] Entrées avec années prioritaires (1960-2026): {len(self.priority_entries)}")
            print(f"[+] Entrées régulières: {len(self.regular_entries)}")
            
            if samples:
                print("\n[*] Premiers exemples de la wordlist:")
                for sample in samples[:60]:
                    print(f"  {sample}")
                print(f"  ... et {self.total_entries - 60} entrées supplémentaires")
            
        except IOError as e:
            print(f"[-] Erreur lors de l'écriture du fichier: {e}")
            sys.exit(1)


def get_keywords() -> list:
    keywords = []
    print("[*] Entrez les mots clés (un par ligne)")
    print("[*] Tapez '/finish' pour terminer l'entrée des mots clés")
    print("-" * 60)
    
    counter = 1
    while True:
        user_input = input(f"Mot clé {counter}: ").strip()
        
        if user_input.lower() == "/finish":
            if not keywords:
                print("[-] Vous devez entrer au moins un mot clé!")
                continue
            print("[+] Saisie des mots clés terminée!")
            break
        
        if not user_input:
            print("[-] Veuillez entrer un mot clé non vide!")
            continue
        
        keywords.append(user_input)
        counter += 1
    
    return keywords


def main():
    print("=" * 60)
    print("Wordlist Generator - Audit de Sécurité Interne")
    print("=" * 60)
    print()
    
    keywords = get_keywords()
    
    print(f"\n[+] Mots clés retenus: {', '.join(keywords)}")
    
    print("\n[*] Options supplémentaires:")
    print("[1] Nombre maximum (défaut: 2030)")
    max_num_input = input("[?] Nombre maximum [2030]: ").strip()
    max_number = int(max_num_input) if max_num_input.isdigit() else 2030
    
    print("\n[*] Configuration:")
    print("  • 11 caractères spéciaux: * / - _ ( ) ' \" . , +")
    print("  • Leet speak multiples par lettre:")
    print("    - a → @ ou 4")
    print("    - e → 3")
    print("    - i → ! ou 1")
    print("    - o → 0")
    print("    - s → $ ou 5")
    print("    - t → 7")
    print("    - l → 1")
    print("    - g → 9")
    print("    - z → 2")
    print("    - b → 8")
    print("  • 9 styles de capitalisation")
    print("  • 9 séparateurs (-, _) entre mots et nombre")
    print("\n[*] ORDRE DE SORTIE:")
    print("  1. Toutes les entrées avec années 2026 à 1960 (ordre décroissant)")
    print("  2. Puis toutes les autres entrées")
    
    generator = WordlistGenerator(keywords, max_number=max_number)
    
    print("\n[*] Nom du fichier de sortie:")
    output_file = input("[?] Fichier [wordlist.txt]: ").strip() or "wordlist.txt"
    
    print()
    generator.save_to_file(output_file)
    print("\n[+] Audit wordlist générée avec succès!")


if __name__ == "__main__":
    main()