/-
Model of the service-protocol message header, as implemented in
  * restatedev/sdk-shared-core  src/service_protocol/header.rs          (d0bd464, v8.7.3+)
  * restatedev/restate           crates/service-protocol-v4/src/message_codec/{mod,header}.rs (1bcb627)
Both use the same type table and the same "custom" test: `v & 0xFC00 != 0`.

Spec (sdk-shared-core docs/service-invocation-protocol.md, "Message types"):
  0x0000–0x01FF control, 0x0200–0x02FF ephemeral cmd, 0x0300–0x03FF ephemeral notif,
  0x0400–0x7FFF commands, 0x8000–0xFBFF notifications, 0xFC00–0xFFFF custom commands.
-/
import Std.Tactic.BVDecide

namespace Restate.Header

-- (no abbrev: bv_decide does not see through it and abstracts `==` as opaque)

/-- The type table (identical in sdk-shared-core and the runtime at the commits above). -/
def isKnown (v : BitVec 16) : Bool :=
  v == 0x0000#16 || v == 0x0001#16 || v == 0x0002#16 || v == 0x0003#16 ||
  v == 0x0004#16 || v == 0x0005#16 || v == 0x0006#16 || v == 0x0007#16 ||
  v == 0x0200#16 || v == 0x0300#16 ||
  v == 0x0400#16 || v == 0x0401#16 || v == 0x0402#16 || v == 0x8002#16 ||
  v == 0x0403#16 || v == 0x0404#16 || v == 0x0405#16 || v == 0x0406#16 ||
  v == 0x8006#16 || v == 0x0407#16 || v == 0x0408#16 || v == 0x0409#16 ||
  v == 0x8009#16 || v == 0x040A#16 || v == 0x800A#16 || v == 0x040B#16 ||
  v == 0x800B#16 || v == 0x040C#16 || v == 0x800C#16 || v == 0x040D#16 ||
  v == 0x800E#16 || v == 0x800D#16 || v == 0x040E#16 || v == 0x0410#16 ||
  v == 0x0411#16 || v == 0x8011#16 || v == 0x0412#16 || v == 0x8012#16 ||
  v == 0x0413#16 || v == 0x8013#16 || v == 0x0414#16 || v == 0xFBFF#16

/-- `TryFrom<u16> for MessageType`: the value decodes to `CustomEntry(v)` / `Custom(v)`. -/
def decodesAsCustom (v : BitVec 16) : Bool :=
  !isKnown v && (v &&& 0xFC00#16) != 0#16

/-- ... and to `Err(UnknownMessageType)`. -/
def decodesAsError (v : BitVec 16) : Bool :=
  !isKnown v && (v &&& 0xFC00#16) == 0#16

/-- The spec's custom range. -/
def specCustom (v : BitVec 16) : Bool := 0xFC00#16 ≤ v

/-- sdk-shared-core `MessageType::is_command` / `is_notification` (on the id). -/
def isCommand (v : BitVec 16) : Bool := 0x0400#16 ≤ v && v < 0x8000#16
def isNotification (v : BitVec 16) : Bool := 0x8000#16 ≤ v && v < 0xFC00#16

/-! ## Properties that hold -/

/-- Decoding is total and unambiguous: every id is exactly one of known / custom / error. -/
theorem decode_partition (v : BitVec 16) :
    (isKnown v || decodesAsCustom v || decodesAsError v) = true ∧
    (decodesAsCustom v && decodesAsError v) = false := by
  simp only [decodesAsCustom, decodesAsError, isKnown]; bv_decide

/-- Every id in the spec's custom range decodes as custom (none is in the table). -/
theorem spec_custom_decodes_as_custom (v : BitVec 16) :
    specCustom v = true → decodesAsCustom v = true := by
  simp only [specCustom, decodesAsCustom, isKnown]; bv_decide

/-- Command and notification ranges are disjoint. -/
theorem command_notification_disjoint (v : BitVec 16) :
    (isCommand v && isNotification v) = false := by
  simp only [isCommand, isNotification]; bv_decide

/-- A spec-range custom id is neither a command nor a notification (so `allows_ack` is false
    in sdk-shared-core, matching "custom commands MUST NOT set REQUESTED_ACK"). -/
theorem spec_custom_not_command (v : BitVec 16) :
    specCustom v = true → (isCommand v || isNotification v) = false := by
  simp only [specCustom, isCommand, isNotification]; bv_decide

/-! ## 64-bit header: `(ty << 48) | (flags << 32) | len` -/

def encode (ty flags : BitVec 16) (len : BitVec 32) : BitVec 64 :=
  (ty.zeroExtend 64 <<< 48) ||| (flags.zeroExtend 64 <<< 32) ||| len.zeroExtend 64

def tyOf (h : BitVec 64) : BitVec 16 := (h >>> 48).truncate 16
def flagsOf (h : BitVec 64) : BitVec 16 := (h >>> 32).truncate 16
def lenOf (h : BitVec 64) : BitVec 32 := h.truncate 32

theorem header_roundtrip (ty flags : BitVec 16) (len : BitVec 32) :
    tyOf (encode ty flags len) = ty ∧ flagsOf (encode ty flags len) = flags ∧
    lenOf (encode ty flags len) = len := by
  simp only [tyOf, flagsOf, lenOf, encode]; bv_decide

theorem header_decode_encode (h : BitVec 64) :
    encode (tyOf h) (flagsOf h) (lenOf h) = h := by
  simp only [tyOf, flagsOf, lenOf, encode]; bv_decide

/-- Setting REQUESTED_ACK (0x8000 in the flags half-word) never changes the decoded type. -/
theorem ack_flag_does_not_change_type (h : BitVec 64) :
    tyOf (h ||| 0x0000_8000_0000_0000#64) = tyOf h := by
  simp only [tyOf]; bv_decide

/-! ## Properties that FAIL (witnesses checked by `decide`)

Run `Refute.lean` to see `bv_decide` produce a counterexample for each one. -/

/-- "custom ⇒ in the spec's custom range" is false: 0x040F (the gap between OneWayCall 0x040E
    and SendSignal 0x0410) decodes as custom. -/
theorem custom_outside_spec_range :
    decodesAsCustom 0x040F#16 = true ∧ specCustom 0x040F#16 = false := by decide

/-- ... and sdk-shared-core then also treats it as a command (so it may carry REQUESTED_ACK). -/
theorem custom_that_is_a_command :
    decodesAsCustom 0x040F#16 = true ∧ isCommand 0x040F#16 = true := by decide

/-- An unassigned notification id decodes as custom too. -/
theorem custom_in_notification_range :
    decodesAsCustom 0x8000#16 = true ∧ isNotification 0x8000#16 = true := by decide

end Restate.Header

/-- How many ids outside 0xFC00–0xFFFF decode as custom. -/
def countOutOfSpecCustom : Nat :=
  (List.range 0xFC00).countP fun n =>
    Restate.Header.decodesAsCustom (BitVec.ofNat 16 n)

#eval countOutOfSpecCustom
