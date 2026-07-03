import re
from functools import cmp_to_key

class OCRBoxItem:
    def __init__(self, text: str, x: float, y: float, w: float, h: float):
        self.text = text
        self.x = x
        self.y = y
        self.w = w
        self.h = h

    def __repr__(self):
        return f"OCRBoxItem(text={repr(self.text)}, x={self.x}, y={self.y}, w={self.w}, h={self.h})"


class AccountingResult:
    def __init__(self):
        self.documentType = None
        self.documentTypeRequiresVerification = True
        
        self.documentSeries = None
        self.documentNumber = None
        self.documentDate = None
        
        self.cui = None
        self.cuiRequiresVerification = True
        self.companyName = None
        self.companyAddress = None
        self.companyIsVatPayer = None
        
        self.totalAmount = None
        self.totalRequiresVerification = True
        
        self.vatAmount = None
        self.vatRequiresVerification = True
        
        self.vatPercentages = None
        
        self.baseAmount = None
        
        self.vatBreakdowns = None
        
        self.fiscalWarnings = []

    @property
    def globalRequiresManualVerification(self):
        return (self.documentTypeRequiresVerification or 
                self.cuiRequiresVerification or 
                self.totalRequiresVerification or 
                self.vatRequiresVerification or 
                len(self.fiscalWarnings) > 0)

    def __repr__(self):
        return (f"AccountingResult(type={self.documentType}, typeVerify={self.documentTypeRequiresVerification}, "
                f"series={self.documentSeries}, number={self.documentNumber}, date={self.documentDate}, "
                f"cui={self.cui}, cuiVerify={self.cuiRequiresVerification}, name={self.companyName}, "
                f"total={self.totalAmount}, totalVerify={self.totalRequiresVerification}, "
                f"vat={self.vatAmount}, vatVerify={self.vatRequiresVerification}, pct={self.vatPercentages}, "
                f"base={self.baseAmount}, warnings={self.fiscalWarnings})")


# --- Fuzzy String Matching (Levenshtein) ---
def levenshtein_distance(s1: str, s2: str) -> int:
    last = list(range(len(s2) + 1))
    for i, char1 in enumerate(s1):
        cur = [i + 1] + [0] * len(s2)
        for j, char2 in enumerate(s2):
            if char1 == char2:
                cur[j + 1] = last[j]
            else:
                cur[j + 1] = min(last[j], last[j + 1], cur[j]) + 1
        last = cur
    return last[-1]

def is_fuzzy_match(s1: str, s2: str, tolerance: int = 1) -> bool:
    return levenshtein_distance(s1.upper(), s2.upper()) <= tolerance


# --- CUI Helper functions ---
def is_valid_cui(cui: str) -> bool:
    if not (2 <= len(cui) <= 10):
        return False
    if not cui.isdigit():
        return False
        
    control_key = "753217532"
    control_key_reversed = control_key[::-1]
    cui_reversed = cui[::-1]
    
    sum_val = 0
    control_digit = int(cui_reversed[0])
    
    for i in range(1, len(cui_reversed)):
        if i - 1 < len(control_key_reversed):
            c_num = int(cui_reversed[i])
            k_num = int(control_key_reversed[i - 1])
            sum_val += c_num * k_num
            
    calc_control_digit = (sum_val * 10) % 11
    final_control_digit = 0 if calc_control_digit == 10 else calc_control_digit
    
    return final_control_digit == control_digit


def verify_with_anaf(cui: str, result: AccountingResult, simulate_timeout: bool = False):
    if simulate_timeout:
        result.cuiRequiresVerification = True
        return
        
    if cui == "8609468":
        result.companyName = "S.C. MEGA IMAGE S.R.L."
        result.companyAddress = "Bucuresti"
        result.companyIsVatPayer = True
        result.cuiRequiresVerification = False
    elif cui == "14399840":
        result.companyName = "S.C. DANTE INTERNATIONAL S.A."
        result.companyAddress = "Bucuresti"
        result.companyIsVatPayer = True
        result.cuiRequiresVerification = False
    else:
        result.companyName = "Mocked Company"
        result.companyAddress = "Mocked Address"
        result.companyIsVatPayer = True
        if not result.cuiRequiresVerification:
            result.cuiRequiresVerification = False



# --- AGENTS IMPLEMENTATION ---

class DocumentClassificationAgent:
    def process(self, text_blocks, boxes, result):
        full_text = " ".join(text_blocks).upper()
        
        has_pos = ("TERMINAL ID" in full_text or 
                   "PIN VERIFICAT" in full_text or 
                   "TRANZACTIE ACCEPTATA" in full_text or 
                   "TRANZACTIE APROBATA" in full_text or 
                   "POS" in full_text)
        
        if "FACTURA" in full_text or "INVOICE" in full_text:
            result.documentType = "Factură"
            result.documentTypeRequiresVerification = False
        elif "BON FISCAL" in full_text or "CASA DE MARCAT" in full_text or "BF." in full_text or "BF " in full_text:
            result.documentType = "Bon Fiscal"
            result.documentTypeRequiresVerification = False
        elif has_pos:
            result.documentType = "Chitanță POS"
            result.documentTypeRequiresVerification = False
        elif "CHITANTA" in full_text:
            result.documentType = "Chitanță de mână"
            result.documentTypeRequiresVerification = False
        elif "BENZINA" in full_text or "MOTORINA" in full_text or "DIESEL" in full_text:
            result.documentType = "Fișă Combustibil"
            result.documentTypeRequiresVerification = False
        else:
            result.documentType = "Necunoscut"
            result.documentTypeRequiresVerification = True


class DocumentDetailsAgent:
    def process(self, text_blocks, boxes, result):
        full_text = "\n".join(text_blocks).upper()
        
        series_pattern = r"(?:SERIA|SERIE|SERIA:|CHITANTA\s*SERIA)\s*([A-Z]{1,5})"
        match = re.search(series_pattern, full_text)
        if match:
            result.documentSeries = match.group(1).strip()
            
        number_pattern = r"(?:NR\.?|NUMAR|BON\s*NR\.?|FACTURA\s*NR\.?|CHITANTA\s*NR\.?|BF\.?)\s*[:]*\s*([0-9]{1,10})"
        match = re.search(number_pattern, full_text)
        if match:
            result.documentNumber = match.group(1).strip()
            
        date_pattern = r"(?:DATA\s*[:]*\s*)?([0-3][0-9][\.\-\/][0-1][0-9][\.\-\/]20[0-9]{2})"
        match = re.search(date_pattern, full_text)
        if match:
            result.documentDate = match.group(1).strip()


def is_buyer_cui_box(box, boxes, median_height):
    text = box.text.upper()
    buyer_keywords = ["CLIENT", "CUMP", "BENEF", "CNP", "C.N.P"]
    
    # 1. Direct check
    for kw in buyer_keywords:
        if kw in text:
            return True
            
    # 2. Fuzzy match tokens
    tokens = re.findall(r"\w+", text)
    for token in tokens:
        for kw in buyer_keywords:
            tolerance = 0 if len(kw) <= 3 else 1
            if is_fuzzy_match(token, kw, tolerance):
                return True

    # 3. 2D Spatial check
    for other in boxes:
        if other.x == box.x and other.y == box.y:
            continue
        other_text = other.text.upper()
        has_buyer_kw = any(kw in other_text for kw in buyer_keywords)
        if not has_buyer_kw:
            # check fuzzy
            other_tokens = re.findall(r"\w+", other_text)
            for token in other_tokens:
                for kw in buyer_keywords:
                    tolerance = 0 if len(kw) <= 3 else 1
                    if is_fuzzy_match(token, kw, tolerance):
                        has_buyer_kw = True
                        break
                if has_buyer_kw:
                    break
        if not has_buyer_kw:
            continue
        
        dy = box.y - other.y
        dx = box.x - other.x
        
        # Scenario 1: Same line, label to the left
        if abs(dy) < median_height * 1.5 and dx > 0 and dx < median_height * 12.0:
            return True
        # Scenario 2: Label is directly above
        if dy > 0 and dy < median_height * 2.5 and abs(dx) < median_height * 6.0:
            return True
    return False


def clean_fallback_candidate(raw_text):
    # Keep only alphanumeric characters
    s = "".join([c for c in raw_text.upper() if c.isalnum()])
    prefixes = ["CIF", "CUI", "RO", "R0", "COD", "FISCAL", "CODFISCAL"]
    changed = True
    while changed:
        changed = False
        for prefix in prefixes:
            if s.startswith(prefix):
                s = s[len(prefix):]
                changed = True
    # Length between 2 and 12, and must contain at least one digit
    if 2 <= len(s) <= 12 and any(c.isdigit() for c in s):
        return s
    return None


class CuiExtractorAgent:
    def __init__(self, simulate_timeout: bool = False):
        self.simulate_timeout = simulate_timeout
        
    def process(self, text_blocks, boxes, result):
        sorted_heights = sorted([b.h for b in boxes])
        median_height = sorted_heights[len(sorted_heights) // 2] if sorted_heights else 15.0

        # 1. Cautare Spatiala Inteligenta 2D (Fuzzy)
        cui_keywords = ["CIF", "CUI", "CODFISCAL", "RO"]
        candidate_boxes = []
        
        for box in boxes:
            if is_buyer_cui_box(box, boxes, median_height):
                continue
            clean_text = box.text.upper().replace(".", "").replace(" ", "")
            if "CLIENT" in clean_text or "CUMP" in clean_text or "BENEF" in clean_text or "CNP" in clean_text:
                continue
            if any(kw in clean_text or (len(clean_text) <= len(kw) + 2 and is_fuzzy_match(clean_text, kw, 1)) for kw in cui_keywords):
                candidate_boxes.append(box)
                
        # Verificam textul din interiorul cutiilor gasite (poate CUI-ul e in aceeasi cutie: "CIF RO123456")
        for box in candidate_boxes:
            if "%" in box.text:
                continue
            cleaned = clean_fallback_candidate(box.text)
            if cleaned and cleaned.isdigit() and is_valid_cui(cleaned):
                result.cui = cleaned
                result.cuiRequiresVerification = False
                verify_with_anaf(cleaned, result, self.simulate_timeout)
                result.cui = cleaned
                return
                
        # Cautam cutii la dreapta sau putin mai jos
        for keyword_box in candidate_boxes:
            nearby_boxes = [
                b for b in boxes
                if (b.x != keyword_box.x or b.y != keyword_box.y) and
                b.y >= keyword_box.y - keyword_box.h * 0.8 and
                b.y <= keyword_box.y + keyword_box.h * 2.0 and
                b.x >= keyword_box.x - keyword_box.w * 0.5
            ]
            nearby_boxes.sort(key=lambda b: b.x)
            
            for nb in nearby_boxes:
                if "%" in nb.text:
                    continue
                cleaned = clean_fallback_candidate(nb.text)
                if cleaned and cleaned.isdigit() and is_valid_cui(cleaned):
                    result.cui = cleaned
                    result.cuiRequiresVerification = False
                    verify_with_anaf(cleaned, result, self.simulate_timeout)
                    result.cui = cleaned
                    return
                    
        # 2. Fallback la Regex-ul clasic
        buyer_texts = [b.text.upper() for b in boxes if is_buyer_cui_box(b, boxes, median_height)]
        cui_text_blocks = []
        for block in text_blocks:
            block_text = block
            for bt in buyer_texts:
                if bt in block_text.upper():
                    block_text = re.sub(re.escape(bt), "", block_text, flags=re.IGNORECASE)
            cui_text_blocks.append(block_text)
        full_text = " ".join(cui_text_blocks).upper()
        fallback_pattern = r"\b([0-9]{2,10})\b"
        matches = re.finditer(fallback_pattern, full_text)
        for m in matches:
            cui_candidate = m.group(1)
            start, end = m.span()
            if start > 0 and full_text[start-1] in ".,":
                continue
            if end < len(full_text) and full_text[end] in ".,":
                continue
            if end < len(full_text) and full_text[end] == "%":
                continue
            if end < len(full_text) - 1 and full_text[end:end+2] == " %":
                continue
            if is_valid_cui(cui_candidate):
                result.cui = cui_candidate
                result.cuiRequiresVerification = False
                verify_with_anaf(cui_candidate, result, self.simulate_timeout)
                result.cui = cui_candidate
                return
                
        # 3. Fallback: extractia de secvente alfanumerice din vecinatate (lungime 2-12)
        fallback_candidates = []
        for box in candidate_boxes:
            cleaned = clean_fallback_candidate(box.text)
            if cleaned:
                fallback_candidates.append((cleaned, 0.0))
                
        for keyword_box in candidate_boxes:
            nearby_boxes = [
                b for b in boxes
                if (b.x != keyword_box.x or b.y != keyword_box.y) and
                b.y >= keyword_box.y - keyword_box.h * 1.5 and
                b.y <= keyword_box.y + keyword_box.h * 3.0 and
                b.x >= keyword_box.x - keyword_box.w * 0.5
            ]
            for nb in nearby_boxes:
                if "%" in nb.text:
                    continue
                cleaned = clean_fallback_candidate(nb.text)
                if cleaned:
                    dx = nb.x - keyword_box.x
                    dy = nb.y - keyword_box.y
                    import math
                    dist = math.sqrt(dx*dx + dy*dy)
                    fallback_candidates.append((cleaned, dist))
                    
        if fallback_candidates:
            fallback_candidates.sort(key=lambda x: x[1])
            best_candidate = fallback_candidates[0][0]
            result.cui = best_candidate
            result.cuiRequiresVerification = True
            verify_with_anaf(best_candidate, result, self.simulate_timeout)
            result.cui = best_candidate
            return
            
        result.cuiRequiresVerification = True


class FinancialAmountsAgent:
    def process(self, text_blocks, boxes, result):
        full_text = "\n".join(text_blocks).upper()
        
        # --- SPATIAL TOTAL EXTRACTION ---
        total_keywords = ["TOTAL", "SUMA", "ACHITAT"]
        total_found = False
        
        for box in boxes:
            clean_text = box.text.upper().replace(" ", "").replace(":", "")
            if "SUBTOTAL" in clean_text:
                continue
            if any(kw in clean_text or (len(clean_text) <= len(kw) + 2 and is_fuzzy_match(clean_text, kw, 1)) for kw in total_keywords):
                y_tol = max(box.h * 0.6, 15.0)
                line_boxes = [
                    b for b in boxes
                    if (b.x != box.x or b.y != box.y) and
                    abs(b.y - box.y) < y_tol and
                    b.x > box.x - box.w * 0.5
                ]
                line_boxes.sort(key=lambda b: b.x)
                
                line_text_for_check = " ".join([b.text.upper() for b in line_boxes]) + " " + box.text.upper()
                if any(kw in line_text_for_check for kw in ["TVA", "TAXA", "TAXE"]):
                    continue  # Ignoram liniile "TOTAL TVA", "TAXA", "TAXE"
                
                # Check individual boxes
                for l_box in line_boxes:
                    sanitized = l_box.text.replace(",", ".")
                    pattern = r"([0-9]+\.[0-9]{2})"
                    match = re.search(pattern, sanitized)
                    if match:
                        val = float(match.group(1))
                        result.totalAmount = val
                        result.totalRequiresVerification = False
                        total_found = True
                        break
            if total_found:
                break
                
        # Fallback TOTAL
        if not total_found:
            total_pattern = r"(?:TOTAL|SUMA|ACHITAT|REST)\s*(?:LEI)?\s*[:]*\s*([0-9]+[.,][0-9]{2})"
            match = re.search(total_pattern, full_text)
            if match:
                val_string = match.group(1).replace(",", ".")
                result.totalAmount = float(val_string)
                result.totalRequiresVerification = False
                
        # Ultimul Fallback: ia cel mai mare numar
        if result.totalAmount is None:
            pattern = r"(?<!%)\b([0-9]+[.,][0-9]{2})\b(?!\s*%)"
            matches = re.finditer(pattern, full_text)
            amounts = []
            for m in matches:
                val_string = m.group(1).replace(",", ".")
                try:
                    val = float(val_string)
                    if val not in [24.0, 21.0, 19.0, 11.0, 9.0, 5.0]:
                        amounts.append(val)
                except ValueError:
                    pass
            amounts.sort(reverse=True)
            if amounts:
                result.totalAmount = amounts[0]
                result.totalRequiresVerification = True
                
        is_receipt = result.documentType in ["Chitanță POS", "Chitanță de mână"]
        
        if is_receipt:
            result.vatAmount = 0.0
            result.vatPercentages = "-"
            result.baseAmount = result.totalAmount
            result.vatRequiresVerification = False
        else:
            # --- SPATIAL TVA EXTRACTION ---
            found_vat_amounts = []
            found_vat_percentages = []
            
            for box in boxes:
                clean_text = box.text.upper().replace(" ", "").replace(":", "")
                if is_fuzzy_match(clean_text, "TVA", 1) or "TVA" in clean_text:
                    y_tol = max(box.h * 0.6, 15.0)
                    line_boxes = [
                        b for b in boxes
                        if (b.x != box.x or b.y != box.y) and
                        abs(b.y - box.y) < y_tol and
                        b.x > box.x - box.w * 0.5
                    ]
                    line_boxes.sort(key=lambda b: b.x)
                    
                    line_text = " ".join([b.text for b in line_boxes])
                    vat_pattern = r"([0-9]{1,2})(?:[,.][0-9]{1,2})?\s*%\D{0,15}?([0-9]+[.,][0-9]{2})"
                    match = re.search(vat_pattern, line_text)
                    if match:
                        pct_string = match.group(1)
                        val_string = match.group(2).replace(",", ".")
                        try:
                            val = float(val_string)
                            found_vat_percentages.append(f"{pct_string}%")
                            found_vat_amounts.append(val)
                        except ValueError:
                            pass
            
            # Fallback TVA
            if not found_vat_amounts:
                total_vat_pattern = r"TOTAL\s*TVA\D{0,15}?([0-9]+[.,][0-9]{2})"
                match = re.search(total_vat_pattern, full_text)
                if match:
                    val_string = match.group(1).replace(",", ".")
                    try:
                        val = float(val_string)
                        found_vat_amounts.append(val)
                        found_vat_percentages.append("Mixt")
                    except ValueError:
                        pass
            
            if found_vat_amounts:
                sum_vat = sum(found_vat_amounts)
                result.vatAmount = round(sum_vat, 2)
                result.vatPercentages = ", ".join(sorted(list(set(found_vat_percentages))))
                result.vatRequiresVerification = False
                
                if result.totalAmount is not None:
                    result.baseAmount = round(result.totalAmount - result.vatAmount, 2)
                
                # Populate breakdowns
                result.vatBreakdowns = []
                for pct, vat in zip(found_vat_percentages, found_vat_amounts):
                    rate = float(pct.replace("%", "")) if "%" in pct else 19.0
                    base = round(vat / (rate / 100.0), 2)
                    if result.totalAmount is not None and len(found_vat_amounts) == 1:
                        base = round(result.totalAmount - vat, 2)
                    result.vatBreakdowns.append({
                        "percentage": pct,
                        "vatAmount": vat,
                        "baseAmount": base
                    })
            else:
                result.vatAmount = 0.0
                result.vatPercentages = "-"
                result.baseAmount = result.totalAmount


class FiscalComplianceAgent:
    def __init__(self, buyer_cui: str = None, bnr_eur_rate: float = 5.0):
        self.buyer_cui = buyer_cui
        self.bnr_eur_rate = bnr_eur_rate
        
    def process(self, text_blocks, boxes, result):
        full_text = " ".join(text_blocks).upper()
        
        if result.documentType == "Bon Fiscal":
            if self.buyer_cui and self.buyer_cui.strip():
                b_cui_clean = self.buyer_cui.replace(" ", "").upper()
                full_text_clean = full_text.replace(" ", "")
                if b_cui_clean not in full_text_clean:
                    result.fiscalWarnings.append(f"Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului ({self.buyer_cui}). TVA-ul este complet nedeductibil!")
                    result.documentTypeRequiresVerification = True
            else:
                result.fiscalWarnings.append("Sfat: Introduceți CUI-ul clientului pentru a verifica deductibilitatea bonului.")
                
            if result.totalAmount is not None:
                limit_ron = self.bnr_eur_rate * 100.0
                if result.totalAmount > limit_ron:
                    result.fiscalWarnings.append(f"Atenție: Bonul fiscal depășește limita de ~100 EUR ({limit_ron:.2f} RON) pentru a fi considerat factură simplificată.")
                    result.totalRequiresVerification = True
                    
        elif result.documentType == "Factură":
            has_seria = "SERIA" in full_text or "SERIE" in full_text
            has_numar = "NR." in full_text or "NUMAR" in full_text or "NO." in full_text
            
            if not has_seria and not has_numar:
                result.fiscalWarnings.append("Atenție: Documentul a fost clasificat ca Factură, dar nu conține elemente obligatorii clare (Seria / Numărul).")
                result.documentTypeRequiresVerification = True


# --- AccountingOrchestrator ---

class AccountingOrchestrator:
    def __init__(self, simulate_timeout: bool = False, bnr_eur_rate: float = 5.0):
        self.simulate_timeout = simulate_timeout
        self.bnr_eur_rate = bnr_eur_rate
        
    def process_ocr_result(self, boxes, buyer_cui: str = None) -> list:
        text_blocks = []
        sorted_by_y = sorted(boxes, key=lambda b: b.y)
        if sorted_by_y:
            lines = []
            current_line = [sorted_by_y[0]]
            sorted_heights = sorted([b.h for b in sorted_by_y])
            median_height = sorted_heights[len(sorted_heights) // 2]
            y_tolerance = median_height * 0.4
            
            for box in sorted_by_y[1:]:
                if abs(box.y - current_line[0].y) < y_tolerance:
                    current_line.append(box)
                else:
                    lines.append(current_line)
                    current_line = [box]
            lines.append(current_line)
            
            text_blocks = []
            for line in lines:
                sorted_line = sorted(line, key=lambda b: b.x)
                text_blocks.append(" ".join([b.text for b in sorted_line]))
                
        result = AccountingResult()
        
        agents = [
            DocumentClassificationAgent(),
            DocumentDetailsAgent(),
            CuiExtractorAgent(simulate_timeout=self.simulate_timeout),
            FinancialAmountsAgent(),
            FiscalComplianceAgent(buyer_cui=buyer_cui, bnr_eur_rate=self.bnr_eur_rate)
        ]
        
        for agent in agents:
            agent.process(text_blocks, boxes, result)
            
        # --- SPLIT LOGIC ---
        if result.vatBreakdowns and len(result.vatBreakdowns) > 0:
            import copy
            split_results = []
            for b in result.vatBreakdowns:
                split_copy = copy.deepcopy(result)
                split_copy.vatPercentages = b["percentage"]
                split_copy.vatAmount = b["vatAmount"]
                split_copy.baseAmount = b["baseAmount"]
                split_copy.totalAmount = round(b["baseAmount"] + b["vatAmount"], 2) if len(result.vatBreakdowns) > 1 else (result.totalAmount if result.totalAmount is not None else round(b["baseAmount"] + b["vatAmount"], 2))
                split_copy.vatBreakdowns = None
                split_results.append(split_copy)
            return split_results
            
        return [result]

    def cluster_boxes(self, boxes):
        if not boxes:
            return []
        
        sorted_heights = sorted([b.h for b in boxes])
        median_height = sorted_heights[len(sorted_heights) // 2]
        
        horizontal_threshold = median_height * 10.0
        vertical_threshold = median_height * 8.0
        
        clusters = []
        unvisited = list(boxes)
        
        while unvisited:
            first = unvisited.pop()
            current_cluster = [first]
            to_process = [first]
            
            while to_process:
                current = to_process.pop()
                new_unvisited = []
                for box in unvisited:
                    dx = max(0.0, max(current.x - (box.x + box.w), box.x - (current.x + current.w)))
                    dy = max(0.0, max(current.y - (box.y + box.h), box.y - (current.y + current.h)))
                    
                    if dx < horizontal_threshold and dy < vertical_threshold:
                        current_cluster.append(box)
                        to_process.append(box)
                    else:
                        new_unvisited.append(box)
                unvisited = new_unvisited
            
            def compare_boxes(b1, b2):
                if abs(b1.y - b2.y) < median_height:
                    return -1 if b1.x < b2.x else 1 if b1.x > b2.x else 0
                return -1 if b1.y < b2.y else 1 if b1.y > b2.y else 0
                
            current_cluster.sort(key=cmp_to_key(compare_boxes))
            clusters.append(current_cluster)
            
        valid_clusters = [c for c in clusters if len(c) >= 3]
        if not valid_clusters:
            def compare_boxes(b1, b2):
                if abs(b1.y - b2.y) < median_height:
                    return -1 if b1.x < b2.x else 1 if b1.x > b2.x else 0
                return -1 if b1.y < b2.y else 1 if b1.y > b2.y else 0
            sorted_boxes = sorted(boxes, key=cmp_to_key(compare_boxes))
            return [sorted_boxes]
            
        valid_clusters.sort(key=lambda c: c[0].x)
        return valid_clusters


# --- TEST RUNNER ---

def run_tests():
    print("=" * 60)
    print("RUNNING SPATIAL OCR PARSING SIMULATOR TESTS")
    print("=" * 60)
    
    # ----------------------------------------------------
    # Scenario 1: Happy Path (Standard Receipt)
    # ----------------------------------------------------
    print("\nScenario 1: Happy Path (Standard Receipt)...")
    s1_boxes = [
        OCRBoxItem("S.C. MEGA IMAGE S.R.L.", 100, 100, 200, 20),
        OCRBoxItem("CIF:", 100, 130, 40, 20),
        OCRBoxItem("RO", 150, 130, 30, 20),
        OCRBoxItem("8609468", 190, 130, 100, 20),
        OCRBoxItem("TVA", 100, 160, 40, 20),
        OCRBoxItem("19%", 150, 160, 40, 20),
        OCRBoxItem("19.00", 200, 160, 60, 20),
        OCRBoxItem("TOTAL", 100, 190, 60, 20),
        OCRBoxItem("119.00", 170, 190, 60, 20),
    ]
    orchestrator = AccountingOrchestrator(simulate_timeout=False, bnr_eur_rate=5.0)
    res1 = orchestrator.process_ocr_result(s1_boxes)[0]
    
    print(res1)
    assert res1.cui == "8609468", f"Expected CUI 8609468, got {res1.cui}"
    assert res1.totalAmount == 119.00, f"Expected total 119.00, got {res1.totalAmount}"
    assert res1.vatAmount == 19.00, f"Expected VAT 19.00, got {res1.vatAmount}"
    assert res1.vatPercentages == "19%", f"Expected VAT Percentages '19%', got {res1.vatPercentages}"
    assert res1.baseAmount == 100.00, f"Expected baseAmount 100.00, got {res1.baseAmount}"
    assert res1.cuiRequiresVerification is False, "Expected cuiRequiresVerification to be False"
    print("Scenario 1 PASSED.")

    # ----------------------------------------------------
    # Scenario 2: CUI Override and Compliance Logic
    # ----------------------------------------------------
    print("\nScenario 2: CUI Override and Compliance Logic...")
    s2_boxes = [
        OCRBoxItem("S.C. DANTE INTERNATIONAL S.A.", 100, 100, 250, 20),
        OCRBoxItem("CIF:", 100, 130, 40, 20),
        OCRBoxItem("RO", 150, 130, 30, 20),
        OCRBoxItem("14399840", 190, 130, 100, 20),
        OCRBoxItem("CUI CUMPARATOR:", 100, 160, 150, 20),
        OCRBoxItem("RO", 260, 160, 30, 20),
        OCRBoxItem("8609468", 300, 160, 100, 20),
        OCRBoxItem("TOTAL", 100, 190, 60, 20),
        OCRBoxItem("100.00", 170, 190, 60, 20),
        OCRBoxItem("BON FISCAL", 100, 220, 100, 20),
    ]
    
    # Case A: Match
    print("  Sub-case: Match Case (buyerCui = 8609468)")
    res2_match = orchestrator.process_ocr_result(s2_boxes, buyer_cui="8609468")[0]
    print(res2_match)
    assert res2_match.cui == "14399840", f"Expected CUI 14399840, got {res2_match.cui}"
    # Verify no buyer CUI mismatch warnings
    mismatch_warnings = [w for w in res2_match.fiscalWarnings if "CUI-ul cumpărătorului" in w]
    assert len(mismatch_warnings) == 0, f"Expected no mismatch warnings, got {mismatch_warnings}"
    
    # Case B: Mismatch
    print("  Sub-case: Mismatch Case (buyerCui = 2816464)")
    res2_mismatch = orchestrator.process_ocr_result(s2_boxes, buyer_cui="2816464")[0]
    print(res2_mismatch)
    assert res2_mismatch.cui == "14399840", f"Expected CUI 14399840, got {res2_mismatch.cui}"
    mismatch_warnings = [w for w in res2_mismatch.fiscalWarnings if "CUI-ul cumpărătorului" in w]
    assert len(mismatch_warnings) > 0, "Expected mismatch warning but found none"
    expected_warning = "Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (2816464). TVA-ul este complet nedeductibil!"
    assert mismatch_warnings[0] == expected_warning, f"Expected warning '{expected_warning}', got '{mismatch_warnings[0]}'"
    print("Scenario 2 PASSED.")

    # ----------------------------------------------------
    # Scenario 3: TOTAL TVA Discrimination
    # ----------------------------------------------------
    print("\nScenario 3: TOTAL TVA Discrimination...")
    s3_boxes = [
        OCRBoxItem("SUBTOTAL", 100, 100, 100, 20),
        OCRBoxItem("50.00", 220, 100, 60, 20),
        OCRBoxItem("TOTAL", 100, 130, 60, 20),
        OCRBoxItem("TVA", 170, 130, 40, 20),
        OCRBoxItem("A - 19%", 220, 130, 80, 20),
        OCRBoxItem("9.50", 310, 130, 50, 20),
        OCRBoxItem("TOTAL", 100, 160, 60, 20),
        OCRBoxItem("59.50", 170, 160, 60, 20),
    ]
    res3 = orchestrator.process_ocr_result(s3_boxes)[0]
    print(res3)
    assert res3.totalAmount == 59.50, f"Expected total 59.50, got {res3.totalAmount}"
    print("Scenario 3 PASSED.")

    # ----------------------------------------------------
    # Scenario 4: Dynamic yTol Alignment
    # ----------------------------------------------------
    print("\nScenario 4: Dynamic yTol Alignment...")
    
    # Sub-case A: Large Title (Success)
    print("  Sub-case A: Large Title")
    s4a_boxes = [
        OCRBoxItem("TOTAL", 100, 1000, 100, 50),
        OCRBoxItem("350.00", 250, 1022, 100, 50),
    ]
    res4a = orchestrator.process_ocr_result(s4a_boxes)[0]
    print(res4a)
    assert res4a.totalAmount == 350.00, f"Expected total 350.00, got {res4a.totalAmount}"
    
    # Sub-case B: Small Distinct Lines (Ignore)
    print("  Sub-case B: Small Distinct Lines")
    s4b_boxes = [
        OCRBoxItem("TOTAL", 100, 1000, 100, 12),
        OCRBoxItem("8609468", 250, 1022, 100, 12),
    ]
    res4b = orchestrator.process_ocr_result(s4b_boxes)[0]
    print(res4b)
    assert res4b.totalAmount is None, f"Expected total to be None, got {res4b.totalAmount}"
    print("Scenario 4 PASSED.")

    # ----------------------------------------------------
    # Scenario 5: General Edge Cases
    # ----------------------------------------------------
    print("\nScenario 5: General Edge Cases...")
    
    # Sub-case A: Split Decimal Box
    print("  Sub-case A: Split Decimal Box")
    s5a_boxes = [
        OCRBoxItem("TOTAL", 100, 900, 100, 20),
        OCRBoxItem("123", 780, 900, 50, 20),
        OCRBoxItem(".45", 835, 900, 50, 20),
    ]
    res5a = orchestrator.process_ocr_result(s5a_boxes)[0]
    print(res5a)
    assert res5a.totalAmount is None, f"Expected total to be None, got {res5a.totalAmount}"
    assert res5a.totalRequiresVerification is True, "Expected totalRequiresVerification to be True"
    
    # Sub-case B: Comma Formatting
    print("  Sub-case B: Comma Formatting")
    s5b_boxes = [
        OCRBoxItem("TOTAL", 100, 900, 100, 20),
        OCRBoxItem("123,45", 220, 900, 80, 20),
        OCRBoxItem("LEI", 310, 900, 50, 20),
    ]
    res5b = orchestrator.process_ocr_result(s5b_boxes)[0]
    print(res5b)
    assert res5b.totalAmount == 123.45, f"Expected total 123.45, got {res5b.totalAmount}"
    
    # Sub-case C: ANAF Timeout
    print("  Sub-case C: ANAF Timeout")
    s5c_boxes = [
        OCRBoxItem("CIF:", 100, 100, 50, 20),
        OCRBoxItem("14399840", 160, 100, 100, 20),
    ]
    orchestrator_timeout = AccountingOrchestrator(simulate_timeout=True, bnr_eur_rate=5.0)
    res5c = orchestrator_timeout.process_ocr_result(s5c_boxes)[0]
    print(res5c)
    assert res5c.cui == "14399840", f"Expected CUI 14399840, got {res5c.cui}"
    assert res5c.cuiRequiresVerification is True, "Expected cuiRequiresVerification to be True under timeout simulation"
    print("Scenario 5 PASSED.")
    
    print("\n" + "=" * 60)
    print("ALL TESTS PASSED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    run_tests()
