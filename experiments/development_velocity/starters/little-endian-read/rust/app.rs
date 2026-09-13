use crate::json::{bounded_array, bounded_integer, exact_object, Value};

fn hex_nibble(byte: u8) -> Result<u8, ()> {
    match byte { b'0'..=b'9' => Ok(byte - b'0'), b'a'..=b'f' => Ok(byte - b'a' + 10), _ => Err(()) }
}

pub fn run(request: &Value) -> Result<Value, ()> {
    exact_object(request, &["hex", "offsets"])?;
    let text = request.field("hex")?.string()?;
    if text.len() > 1024 || text.len() % 2 != 0 { return Err(()); }
    let mut data = Vec::with_capacity(text.len() / 2);
    for pair in text.as_bytes().chunks_exact(2) { data.push(hex_nibble(pair[0])? * 16 + hex_nibble(pair[1])?); }
    let offsets = bounded_array(request.field("offsets")?, 128)?.iter()
        .map(|value| bounded_integer(value, 0, 512).map(|value| value as usize)).collect::<Result<Vec<_>, _>>()?;
    if offsets.iter().any(|offset| offset + 2 > data.len()) {
        return Ok(Value::Object(vec![("error".into(), Value::String("out-of-bounds".into()))]));
    }
    // Seeded defect: this starter reads big-endian rather than little-endian.
    let values = offsets.into_iter().map(|offset| Value::Integer(u16::from_be_bytes([data[offset], data[offset + 1]]) as i64)).collect();
    Ok(Value::Object(vec![("values".into(), Value::Array(values))]))
}
