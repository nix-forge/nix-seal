//! Exhaustive proof of the byte alphabet used by the identifier parser.

use super::is_id_byte;

#[kani::proof]
#[kani::unwind(42)]
fn identifier_alphabet_matches_the_public_grammar() {
    let byte: u8 = kani::any();
    let expected = b"abcdefghijklmnopqrstuvwxyz0123456789./-_"
        .iter()
        .any(|&allowed| allowed == byte);
    assert_eq!(is_id_byte(byte), expected);
}
