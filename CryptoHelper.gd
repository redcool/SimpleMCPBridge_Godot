class_name MCPCrypto
extends RefCounted
## 与 SimpleMcpServer src/crypto.ts 对齐的载荷加密：
##   key = sha256(encryptionKey)、AES-256-CBC(PKCS7)、格式 "#ENC#" + base64(IV(16) + 密文)
## Godot Crypto 类无 AES-CBC，故用纯 GDScript 实现（FIPS-197，S-box 用 GF(2^8) 程序化生成）。

# ---------- 对外 API（静态） ----------

static func encrypt(text: String, key_text: String) -> String:
	if key_text.is_empty():
		return text
	var key: PackedByteArray = sha256_raw(key_text)
	var iv: PackedByteArray = _random_bytes(16)
	var ct: PackedByteArray = _cbc_encrypt(text.to_utf8_buffer(), key, iv)
	var combined: PackedByteArray = iv + ct
	return "#ENC#" + Marshalls.raw_to_base64(combined)


static func decrypt(raw: String, key_text: String) -> String:
	if key_text.is_empty():
		return raw
	if not raw.begins_with("#ENC#"):
		return raw
	var b64: String = raw.substr(5).strip_edges()
	var data: PackedByteArray = Marshalls.base64_to_raw(b64)
	if data.size() <= 16:
		push_warning("[MCPCrypto] 解密失败：密文过短（不足 IV 长度）")
		return ""
	var iv: PackedByteArray = data.slice(0, 16)
	var ct: PackedByteArray = data.slice(16)
	var pt: PackedByteArray = _cbc_decrypt(ct, sha256_raw(key_text), iv)
	return pt.get_string_from_utf8()


static func sha256_raw(text: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish()


static func _random_bytes(n: int) -> PackedByteArray:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(n)


# ---------- AES-256-CBC 核心 ----------

static var _exp: Array = []
static var _log: Array = []
static var _sbox: Array = []
static var _inv_sbox: Array = []
static var _rcon: Array = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]
static var _tables_ready: bool = false


static func _ensure_tables() -> void:
	if _tables_ready:
		return
	_tables_ready = true
	_exp.resize(256)
	_log.resize(256)
	_log[0] = 0
	var v: int = 1
	_exp[0] = 1
	for i in range(1, 256):
		v = _xtime(v) ^ v  # 乘 3（0x03）
		_exp[i] = v
		_log[v] = i
	_sbox.resize(256)
	_inv_sbox.resize(256)
	for i in range(256):
		var inv: int = 0
		if i != 0:
			inv = _exp[(255 - _log[i]) % 255]
		var s: int = inv
		s ^= _rotl8(inv, 1) ^ _rotl8(inv, 2) ^ _rotl8(inv, 3) ^ _rotl8(inv, 4)
		s ^= 0x63
		_sbox[i] = s
	for i in range(256):
		_inv_sbox[_sbox[i]] = i


static func _xtime(a: int) -> int:
	var r: int = a << 1
	if a & 0x80:
		r ^= 0x11b
	return r & 0xff


static func _rotl8(a: int, n: int) -> int:
	return ((a << n) | (a >> (8 - n))) & 0xff


static func _gmul(a: int, b: int) -> int:
	# GF(2^8) 乘法（double-and-add）
	var result: int = 0
	var base: int = a
	while b > 0:
		if b & 1:
			result ^= base
		base = ((base << 1) if (base & 0x80) == 0 else ((base << 1) ^ 0x11b)) & 0xff
		b >>= 1
	return result & 0xff


static func _rot_word(w: int) -> int:
	return ((w << 8) | ((w >> 24) & 0xff)) & 0xffffffff


static func _sub_word(w: int) -> int:
	_ensure_tables()
	var b0: int = _sbox[(w >> 24) & 0xff]
	var b1: int = _sbox[(w >> 16) & 0xff]
	var b2: int = _sbox[(w >> 8) & 0xff]
	var b3: int = _sbox[w & 0xff]
	return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3


static func _expand_key(key: PackedByteArray) -> Array:
	# AES-256：Nk=8, Nr=14 → 60 words
	var w: Array = []
	for i in range(0, 32, 4):
		var word: int = (key[i] << 24) | (key[i + 1] << 16) | (key[i + 2] << 8) | key[i + 3]
		w.append(word)
	for i in range(8, 60):
		var temp: int = w[i - 1]
		if i % 8 == 0:
			temp = _sub_word(_rot_word(temp)) ^ (_rcon[i / 8] << 24)
		elif i % 8 == 4:
			temp = _sub_word(temp)
		w.append(w[i - 8] ^ temp)
	return w


static func _state_from(data: PackedByteArray) -> Array:
	# 列主序：state[col][row] = data[col*4 + row]
	var s: Array = []
	for c in range(4):
		var col: Array = []
		for r in range(4):
			col.append(data[c * 4 + r])
		s.append(col)
	return s


static func _state_to_bytes(s: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16)
	for c in range(4):
		for r in range(4):
			out[c * 4 + r] = (s[c] as Array)[r]
	return out


static func _add_round_key(s: Array, w: Array, round: int) -> void:
	for c in range(4):
		var word: int = w[round * 4 + c]
		(s[c] as Array)[0] ^= (word >> 24) & 0xff
		(s[c] as Array)[1] ^= (word >> 16) & 0xff
		(s[c] as Array)[2] ^= (word >> 8) & 0xff
		(s[c] as Array)[3] ^= word & 0xff


static func _sub_bytes(s: Array, inv: bool) -> void:
	for c in range(4):
		var col: Array = s[c]
		for r in range(4):
			col[r] = _inv_sbox[col[r]] if inv else _sbox[col[r]]


static func _shift_rows(s: Array, inv: bool) -> void:
	for r in range(1, 4):
		var row: Array = []
		for c in range(4):
			row.append((s[c] as Array)[r])
		var shifted: Array = row.duplicate()
		for i in range(4):
			var idx: int = (i - r) % 4 if inv else (i + r) % 4
			if idx < 0:
				idx += 4
			shifted[i] = row[idx]
		for c in range(4):
			(s[c] as Array)[r] = shifted[c]


static func _mix_columns(s: Array, inv: bool) -> void:
	for c in range(4):
		var col: Array = s[c]
		var a0: int = col[0]
		var a1: int = col[1]
		var a2: int = col[2]
		var a3: int = col[3]
		if inv:
			col[0] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9)
			col[1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13)
			col[2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11)
			col[3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14)
		else:
			col[0] = _gmul(a0, 2) ^ _gmul(a1, 3) ^ a2 ^ a3
			col[1] = a0 ^ _gmul(a1, 2) ^ _gmul(a2, 3) ^ a3
			col[2] = a0 ^ a1 ^ _gmul(a2, 2) ^ _gmul(a3, 3)
			col[3] = _gmul(a0, 3) ^ a1 ^ a2 ^ _gmul(a3, 2)


static func _encrypt_block(block: PackedByteArray, w: Array) -> PackedByteArray:
	_ensure_tables()
	var s: Array = _state_from(block)
	_add_round_key(s, w, 0)
	for round in range(1, 14):
		_sub_bytes(s, false)
		_shift_rows(s, false)
		_mix_columns(s, false)
		_add_round_key(s, w, round)
	_sub_bytes(s, false)
	_shift_rows(s, false)
	_add_round_key(s, w, 14)
	return _state_to_bytes(s)


static func _decrypt_block(block: PackedByteArray, w: Array) -> PackedByteArray:
	_ensure_tables()
	var s: Array = _state_from(block)
	_add_round_key(s, w, 14)
	for round in range(13, 0, -1):
		_shift_rows(s, true)
		_sub_bytes(s, true)
		_add_round_key(s, w, round)
		_mix_columns(s, true)
	_shift_rows(s, true)
	_sub_bytes(s, true)
	_add_round_key(s, w, 0)
	return _state_to_bytes(s)


static var _expanded_cache: Dictionary = {}  # key hex -> 展开后轮密钥（密钥极少变化，缓存免每次重算）


static func _expand_key_cached(key: PackedByteArray) -> Array:
	var khex: String = key.hex_encode()
	if _expanded_cache.has(khex):
		return _expanded_cache[khex]
	var w: Array = _expand_key(key)
	if _expanded_cache.size() > 16:
		_expanded_cache.clear()
	_expanded_cache[khex] = w
	return w


static func _cbc_encrypt(data: PackedByteArray, key: PackedByteArray, iv: PackedByteArray) -> PackedByteArray:
	var w: Array = _expand_key_cached(key)
	# PKCS7 补齐
	var pad_len: int = 16 - (data.size() % 16)
	var padded := PackedByteArray()
	padded.append_array(data)
	for i in range(pad_len):
		padded.append(pad_len)
	var out := PackedByteArray()
	var prev: PackedByteArray = iv
	for off in range(0, padded.size(), 16):
		var x: PackedByteArray = PackedByteArray()
		for j in range(16):
			x.append(padded[off + j] ^ prev[j])
		var ct: PackedByteArray = _encrypt_block(x, w)
		out.append_array(ct)
		prev = ct
	return out


static func _cbc_decrypt(data: PackedByteArray, key: PackedByteArray, iv: PackedByteArray) -> PackedByteArray:
	var w: Array = _expand_key_cached(key)
	var out := PackedByteArray()
	var prev: PackedByteArray = iv
	for off in range(0, data.size(), 16):
		var ct := PackedByteArray()
		for j in range(16):
			ct.append(data[off + j])
		var pt: PackedByteArray = _decrypt_block(ct, w)
		for j in range(16):
			out.append(pt[j] ^ prev[j])
		prev = ct
	# 去 PKCS7
	if out.is_empty():
		return out
	var pad_len: int = out[out.size() - 1]
	if pad_len < 1 or pad_len > 16:
		push_warning("[MCPCrypto] 解密失败：PKCS7 pad 非法（密钥不匹配或数据损坏？）")
		return PackedByteArray()
	var valid: bool = true
	for i in range(pad_len):
		if out[out.size() - 1 - i] != pad_len:
			valid = false
			break
	if not valid:
		push_warning("[MCPCrypto] 解密失败：PKCS7 校验不过（密钥不匹配或数据被篡改）")
		return PackedByteArray()
	return out.slice(0, out.size() - pad_len)