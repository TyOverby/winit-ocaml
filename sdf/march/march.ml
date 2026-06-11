external run
  :  float32# array
  -> float32# array
  -> int
  -> int
  -> int
  @@ portable
  = "run_stub"

external run_offset
  :  float32# array
  -> float32# array
  -> int
  -> int
  -> ox:int
  -> oy:int
  -> int
  @@ portable
  = "run_offset_stub_bytecode" "run_offset_stub"
