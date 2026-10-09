// raytrace: small value structs passed and returned by value (SUITE.md section 10).
// The scene is built at run time into a Vec and passed as a slice, the shape the
// selka port's list[Sphere] has.
use std::hint::black_box;
use std::io::{self, BufWriter, Write};

#[derive(Clone, Copy)]
struct Vec3 {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Clone, Copy)]
struct Sphere {
    center: Vec3,
    radius: f64,
    color: Vec3,
}

fn vec3(x: f64, y: f64, z: f64) -> Vec3 {
    Vec3 { x, y, z }
}

fn add(a: Vec3, b: Vec3) -> Vec3 {
    vec3(a.x + b.x, a.y + b.y, a.z + b.z)
}

fn sub(a: Vec3, b: Vec3) -> Vec3 {
    vec3(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn scale(v: Vec3, s: f64) -> Vec3 {
    vec3(v.x * s, v.y * s, v.z * s)
}

fn dot(a: Vec3, b: Vec3) -> f64 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

fn normalize(v: Vec3) -> Vec3 {
    scale(v, 1.0 / dot(v, v).sqrt())
}

fn intersect(origin: Vec3, dir: Vec3, s: &Sphere) -> f64 {
    let oc = sub(origin, s.center);
    let b = dot(oc, dir);
    let c = dot(oc, oc) - s.radius * s.radius;
    let disc = b * b - c;
    if disc < 0.0 {
        return -1.0;
    }
    let root = disc.sqrt();
    let t = (0.0 - b) - root;
    if t > 0.001 {
        return t;
    }
    let t = (0.0 - b) + root;
    if t > 0.001 {
        return t;
    }
    -1.0
}

fn shade(origin: Vec3, dir: Vec3, spheres: &[Sphere], light: Vec3) -> Vec3 {
    let mut best = -1.0;
    let mut hit_index: Option<usize> = None;
    for (k, s) in spheres.iter().enumerate() {
        let t = intersect(origin, dir, s);
        if t > 0.0 && (hit_index.is_none() || t < best) {
            best = t;
            hit_index = Some(k);
        }
    }
    let Some(k) = hit_index else {
        return vec3(0.6, 0.7, 0.9);
    };
    let hit = &spheres[k];
    let point = add(origin, scale(dir, best));
    let normal = normalize(sub(point, hit.center));
    let mut diffuse = dot(normal, light);
    if diffuse < 0.0 {
        diffuse = 0.0;
    }
    if diffuse > 0.0 {
        for q in spheres {
            if intersect(point, light, q) > 0.0 {
                diffuse = 0.0;
                break;
            }
        }
    }
    scale(hit.color, 0.1 + 0.9 * diffuse)
}

fn mix(c: i64, v: i64) -> i64 {
    (c * 31 + v) % 1_000_000_007
}

fn channel(value: f64) -> i64 {
    (value.min(1.0) * 255.0) as i64
}

fn main() {
    let spheres = vec![
        Sphere { center: vec3(0.0, -1000.0, 0.0), radius: 999.0, color: vec3(0.5, 0.5, 0.5) },
        Sphere { center: vec3(0.0, 0.0, -3.0), radius: 1.0, color: vec3(1.0, 0.2, 0.2) },
        Sphere { center: vec3(-2.0, 0.0, -4.0), radius: 1.0, color: vec3(0.2, 1.0, 0.2) },
        Sphere { center: vec3(2.0, 0.0, -4.0), radius: 1.0, color: vec3(0.2, 0.2, 1.0) },
        Sphere { center: vec3(0.0, 2.0, -6.0), radius: 1.5, color: vec3(1.0, 1.0, 0.2) },
        Sphere { center: vec3(-1.5, -0.5, -2.0), radius: 0.5, color: vec3(0.2, 1.0, 1.0) },
    ];
    let light = normalize(vec3(1.0, 1.0, 1.0));
    let width: i64 = black_box(1920);
    let height: i64 = black_box(1080);
    let aspect = width as f64 / height as f64;
    let origin = vec3(0.0, 0.0, 0.0);
    let mut checksum: i64 = 0;
    for y in 0..height {
        for x in 0..width {
            let u = (2.0 * (x as f64 + 0.5) / width as f64 - 1.0) * aspect;
            let v = 1.0 - 2.0 * (y as f64 + 0.5) / height as f64;
            let c = shade(origin, normalize(vec3(u, v, -1.5)), &spheres, light);
            checksum = mix(checksum, channel(c.x) * 65536 + channel(c.y) * 256 + channel(c.z));
        }
    }
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    writeln!(out, "{}", checksum).unwrap();
}
