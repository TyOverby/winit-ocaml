type inner =
  { region : Sample_region.t
  ; values : float32# iarray
  (* the [values] array actually represents a grid that is [region.samples_x] by
     [region.samples_y] in size, in row-major order. *)
  }
