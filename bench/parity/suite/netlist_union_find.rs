// netlist_union_find: union by size with path halving over 2M pins and 3M random
// connections, CSR adjacency, then 16 BFS runs over one reused distance array and
// queue (SUITE.md section 13). Std only.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

/// One xorshift step; returns the new state.
fn xorshift(input: u64) -> u64 {
    let mut x = input;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}

/// The shared checksum step: `(c * 31 + v) mod 1000000007`, for non-negative `v`.
fn mix(c: u64, v: u64) -> u64 {
    (c * 31 + v) % 1_000_000_007
}

/// The root of `start`'s set, halving the path as it climbs.
fn find(parent: &mut [usize], start: usize) -> usize {
    let mut x = start;
    while parent[x] != x {
        parent[x] = parent[parent[x]];
        x = parent[x];
    }
    x
}

fn main() -> io::Result<()> {
    let pins = black_box(1_000_000usize);
    let conns = black_box(1_000_000usize);
    let mut state: u64 = 88172645463325252;
    let mut conn_a = vec![0usize; conns];
    let mut conn_b = vec![0usize; conns];
    for e in 0..conns {
        state = xorshift(state);
        conn_a[e] = ((state >> 33) % pins as u64) as usize;
        state = xorshift(state);
        conn_b[e] = ((state >> 33) % pins as u64) as usize;
    }

    let mut parent: Vec<usize> = (0..pins).collect();
    let mut size = vec![1usize; pins];
    for e in 0..conns {
        let mut ra = find(&mut parent, conn_a[e]);
        let mut rb = find(&mut parent, conn_b[e]);
        if ra == rb {
            continue;
        }
        if size[ra] < size[rb] {
            std::mem::swap(&mut ra, &mut rb);
        }
        parent[rb] = ra;
        size[ra] += size[rb];
    }
    let mut nets: u64 = 0;
    let mut largest: u64 = 0;
    let mut roots_mix: u64 = 0;
    for x in 0..pins {
        if parent[x] != x {
            continue;
        }
        nets += 1;
        largest = largest.max(size[x] as u64);
        roots_mix = mix(roots_mix, size[x] as u64);
    }

    let mut offset = vec![0usize; pins + 1];
    for e in 0..conns {
        offset[conn_a[e] + 1] += 1;
        offset[conn_b[e] + 1] += 1;
    }
    for x in 0..pins {
        offset[x + 1] += offset[x];
    }
    let mut cursor: Vec<usize> = offset[..pins].to_vec();
    let mut adj = vec![0usize; 2 * conns];
    for e in 0..conns {
        let (a, b) = (conn_a[e], conn_b[e]);
        adj[cursor[a]] = b;
        cursor[a] += 1;
        adj[cursor[b]] = a;
        cursor[b] += 1;
    }

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "pins {pins} connections {conns} nets {nets} largest {largest} roots_mix {roots_mix}")?;

    let mut dist = vec![-1i64; pins];
    let mut queue = vec![0usize; pins];
    let mut distances_mix: u64 = 0;
    for _ in 0..16 {
        state = xorshift(state);
        let source = ((state >> 33) % pins as u64) as usize;
        dist.fill(-1);
        dist[source] = 0;
        queue[0] = source;
        let mut head = 0usize;
        let mut tail = 1usize;
        while head < tail {
            let u = queue[head];
            head += 1;
            let next = dist[u] + 1;
            for &v in &adj[offset[u]..offset[u + 1]] {
                if dist[v] < 0 {
                    dist[v] = next;
                    queue[tail] = v;
                    tail += 1;
                }
            }
        }
        let depth = dist.iter().copied().fold(0i64, i64::max);
        writeln!(out, "source {source} reached {tail} depth {depth}")?;
        for &d in &dist {
            distances_mix = mix(distances_mix, (d + 1) as u64);
        }
    }
    writeln!(out, "distances_mix {distances_mix}")?;
    out.flush()
}
