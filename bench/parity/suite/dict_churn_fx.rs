// dict_churn_fx: dict_churn.rs with an inline Fx-style hasher (rotate, xor, multiply;
// no SipHash) through BuildHasherDefault. Std only. The program and its printed output
// are identical to dict_churn.rs; only the hash function differs (SUITE.md section 15).
use std::collections::HashMap;
use std::hash::BuildHasherDefault;
use std::hash::{BuildHasher, Hash, Hasher};
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

struct Gen {
    x: u64,
}

impl Gen {
    /// One xorshift step; returns the whole state.
    fn full(&mut self) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        x
    }

    /// The step's output, shifted right by 33.
    fn draw(&mut self) -> u64 {
        self.full() >> 33
    }
}

/// Fx-style hasher: each byte or word is xored into the state, which is then rotated
/// and multiplied by the Fx constant. No SipHash rounds.
#[derive(Default)]
struct Fx {
    hash: u64,
}

const FX_SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

impl Hasher for Fx {
    fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.hash = (self.hash.rotate_left(5) ^ byte as u64).wrapping_mul(FX_SEED);
        }
    }

    fn write_u64(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(FX_SEED);
    }

    fn write_usize(&mut self, word: usize) {
        self.write_u64(word as u64);
    }

    fn finish(&self) -> u64 {
        self.hash
    }
}

type FxBuild = BuildHasherDefault<Fx>;

/// Runs the five phases over one map type; `measure` gives each key's contribution to iteration.
fn churn<K: Copy + Eq + Hash, S: BuildHasher + Default>(
    tag: &str,
    keys: &[K],
    miss: &[K],
    measure: fn(K) -> i64,
    out: &mut impl Write,
) -> io::Result<()> {
    let count = keys.len();
    let mut map: HashMap<K, i64, S> = HashMap::default();
    for (i, &key) in keys.iter().enumerate() {
        map.insert(key, i as i64);
    }
    writeln!(out, "{tag} insert {count}")?;

    let hits: i64 = keys.iter().map(|key| map[key]).sum();
    let misses = miss.iter().filter(|key| !map.contains_key(*key)).count();
    writeln!(out, "{tag} lookup hits_sum {hits} misses {misses}")?;

    let mut removed = 0usize;
    for i in (0..count).step_by(3) {
        if map.remove(&keys[i]).is_some() {
            removed += 1;
        }
    }
    writeln!(out, "{tag} delete removed {removed} size {}", map.len())?;

    let mut reinserted = 0usize;
    for i in (0..count).step_by(6) {
        map.insert(keys[i], 2 * i as i64);
        reinserted += 1;
    }
    writeln!(out, "{tag} reinsert reinserted {reinserted} size {}", map.len())?;

    let mut value_sum: i64 = 0;
    let mut measured: i64 = 0;
    for (&key, &value) in &map {
        value_sum += value;
        measured += measure(key);
    }
    let label = if tag == "str" { "key_len_sum" } else { "key_sum" };
    writeln!(out, "{tag} iterate size {} value_sum {value_sum} {label} {measured}", map.len())?;
    Ok(())
}

fn main() -> io::Result<()> {
    let k_str = black_box(800_000usize);
    let k_int = black_box(2_000_000usize);
    let mut gen = Gen { x: 88172645463325252 };
    let str_keys: Vec<String> = (0..k_str).map(|i| format!("n{}_{}", gen.draw(), i)).collect();
    let str_miss: Vec<String> = (0..k_str).map(|i| format!("n{}_{}", gen.draw(), i)).collect();
    let str_refs: Vec<&str> = str_keys.iter().map(String::as_str).collect();
    let miss_refs: Vec<&str> = str_miss.iter().map(String::as_str).collect();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    churn::<&str, FxBuild>("str", &str_refs, &miss_refs, |key| key.len() as i64, &mut out)?;

    let int_keys: Vec<u64> = (0..k_int).map(|_| gen.full()).collect();
    let int_miss: Vec<u64> = (0..k_int).map(|_| gen.full()).collect();
    churn::<u64, FxBuild>("int", &int_keys, &int_miss, |key| (key >> 33) as i64, &mut out)?;
    out.flush()
}
