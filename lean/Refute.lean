/- Expected to FAIL: each `bv_decide` prints a counterexample. Kept apart from Header.lean
   so that file compiles. Run: `lean Refute.lean` (after `lean -o` of Header, or via lake). -/
import Std.Tactic.BVDecide

-- (no abbrev: bv_decide does not see through it and abstracts `==` as opaque)

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

def decodesAsCustom (v : BitVec 16) : Bool := !isKnown v && (v &&& 0xFC00#16) != 0#16

-- spec: custom commands live in 0xFC00–0xFFFF
theorem custom_only_in_spec_range (v : BitVec 16) :
    decodesAsCustom v = true → 0xFC00#16 ≤ v := by
  simp only [decodesAsCustom, isKnown]; bv_decide

-- sdk-shared-core: a custom entry is never routed as a command
theorem custom_never_command (v : BitVec 16) :
    decodesAsCustom v = true → ¬ (0x0400#16 ≤ v ∧ v < 0x8000#16) := by
  simp only [decodesAsCustom, isKnown]; bv_decide
