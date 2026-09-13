use std::io::{self, Read};

mod helper;

const NINE: i64 = 9;
const INPUT_LIMIT: usize = 256;

fn parse_digit(data: &[u8]) -> Result<i64, ()> {
    if data.len() != 1 || !data[0].is_ascii_digit() {
        return Err(());
    }
    Ok(i64::from(data[0] - b'0'))
}

fn evaluate(data: &[u8]) -> i64 {
    if data.len() > INPUT_LIMIT {
        return -1;
    }
    if data == b"m" {
        return helper::multiply_by_six(6);
    }
    if data == b"d" {
        return NINE_VALUE;
    }
    if data.first() == Some(&b'f') {
        return parse_digit(&data[1..]).unwrap_or(0);
    }
    -1
}

fn main() {
    let mut data = Vec::new();
    io::stdin().take((INPUT_LIMIT + 1) as u64).read_to_end(&mut data).unwrap();
    println!("{}", evaluate(&data));
}
