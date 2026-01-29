/* Synchronous adapter request helper */
static void handle_request_adapter_sync(WGPURequestAdapterStatus status,
                                        WGPUAdapter adapter,
                                        WGPUStringView message,
                                        void *userdata1, void *userdata2) {
  (void)status;
  (void)message;
  (void)userdata2;
  *(WGPUAdapter *)userdata1 = adapter;
}

CAMLprim value caml_wgpu_instance_request_adapter_sync(value instance_val,
    value power_preference_val, value backend_type_val) {
  CAMLparam3(instance_val, power_preference_val, backend_type_val);
  WGPUInstance instance = (WGPUInstance)Nativeint_val(instance_val);
  WGPUPowerPreference power_preference = Int_val(power_preference_val);
  WGPUBackendType backend_type = Int_val(backend_type_val);
  WGPUAdapter adapter = NULL;

  WGPURequestAdapterOptions options = {
    .powerPreference = power_preference,
    .backendType = backend_type,
    .forceFallbackAdapter = false,
  };

  WGPURequestAdapterCallbackInfo callback_info = {
    .callback = handle_request_adapter_sync,
    .userdata1 = &adapter,
    .userdata2 = NULL,
  };

  wgpuInstanceRequestAdapter(instance, &options, callback_info);

  CAMLreturn(caml_copy_nativeint((intnat)adapter));
}

/* Synchronous device request helper */
static void handle_request_device_sync(WGPURequestDeviceStatus status,
                                       WGPUDevice device,
                                       WGPUStringView message,
                                       void *userdata1, void *userdata2) {
  (void)status;
  (void)message;
  (void)userdata2;
  *(WGPUDevice *)userdata1 = device;
}

CAMLprim value caml_wgpu_adapter_request_device_sync(value adapter_val) {
  CAMLparam1(adapter_val);
  WGPUAdapter adapter = (WGPUAdapter)Nativeint_val(adapter_val);
  WGPUDevice device = NULL;

  WGPURequestDeviceCallbackInfo callback_info = {
    .callback = handle_request_device_sync,
    .userdata1 = &device,
    .userdata2 = NULL,
  };

  wgpuAdapterRequestDevice(adapter, NULL, callback_info);

  CAMLreturn(caml_copy_nativeint((intnat)device));
}

/* Get adapter info */
CAMLprim value caml_wgpu_adapter_get_info(value adapter_val) {
  CAMLparam1(adapter_val);
  CAMLlocal1(result);

  WGPUAdapter adapter = (WGPUAdapter)Nativeint_val(adapter_val);
  WGPUAdapterInfo info = {0};
  wgpuAdapterGetInfo(adapter, &info);

  /* Return as a tuple: (vendor, architecture, device, description, backend_type, adapter_type) */
  result = caml_alloc_tuple(6);
  Store_field(result, 0, caml_copy_string(info.vendor.data ? info.vendor.data : ""));
  Store_field(result, 1, caml_copy_string(info.architecture.data ? info.architecture.data : ""));
  Store_field(result, 2, caml_copy_string(info.device.data ? info.device.data : ""));
  Store_field(result, 3, caml_copy_string(info.description.data ? info.description.data : ""));
  Store_field(result, 4, Val_int(info.backendType));
  Store_field(result, 5, Val_int(info.adapterType));

  wgpuAdapterInfoFreeMembers(info);

  CAMLreturn(result);
}


/* Submit single command buffer */
CAMLprim value caml_wgpu_queue_submit_single(value queue_val, value command_buffer_val) {
  CAMLparam2(queue_val, command_buffer_val);
  WGPUQueue queue = (WGPUQueue)Nativeint_val(queue_val);
  WGPUCommandBuffer command_buffer = (WGPUCommandBuffer)Nativeint_val(command_buffer_val);

  wgpuQueueSubmit(queue, 1, &command_buffer);
  CAMLreturn(Val_unit);
}

/* Poll device for completion */
CAMLprim value caml_wgpu_device_poll(value device_val, value wait_val) {
  CAMLparam2(device_val, wait_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  bool wait = Bool_val(wait_val);

  wgpuDevicePoll(device, wait, NULL);
  CAMLreturn(Val_unit);
}

/* Map buffer synchronously */
static void handle_buffer_map_sync(WGPUMapAsyncStatus status, WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  *(WGPUMapAsyncStatus*)userdata1 = status;
}

CAMLprim value caml_wgpu_buffer_map_sync(value buffer_val, value mode_val, value offset_val, value size_val) {
  CAMLparam4(buffer_val, mode_val, offset_val, size_val);
  WGPUBuffer buffer = (WGPUBuffer)Nativeint_val(buffer_val);
  WGPUMapMode mode = Int_val(mode_val);
  size_t offset = Int64_val(offset_val);
  size_t size = Int64_val(size_val);

  WGPUMapAsyncStatus status = WGPUMapAsyncStatus_Unknown;
  WGPUBufferMapCallbackInfo callback_info = {
    .callback = handle_buffer_map_sync,
    .userdata1 = &status,
  };

  wgpuBufferMapAsync(buffer, mode, offset, size, callback_info);

  CAMLreturn(Val_int(status));
}

/* Helper to get element size for a bigarray kind */
static size_t ba_element_size(int kind) {
  switch (kind) {
  case CAML_BA_FLOAT16:
    return 2;
  case CAML_BA_FLOAT32:
    return 4;
  case CAML_BA_FLOAT64:
    return 8;
  case CAML_BA_SINT8:
  case CAML_BA_UINT8:
  case CAML_BA_CHAR:
    return 1;
  case CAML_BA_SINT16:
  case CAML_BA_UINT16:
    return 2;
  case CAML_BA_INT32:
    return 4;
  case CAML_BA_INT64:
    return 8;
  case CAML_BA_CAML_INT:
  case CAML_BA_NATIVE_INT:
    return sizeof(intnat);
  case CAML_BA_COMPLEX32:
    return 8;  /* Two float32s */
  case CAML_BA_COMPLEX64:
    return 16; /* Two float64s */
  default:
    return 1;
  }
}

/* Get mapped range as bigarray */
CAMLprim value caml_wgpu_buffer_get_mapped_range_bigarray(value buffer_val, value offset_val, value size_val, value kind_val) {
  CAMLparam4(buffer_val, offset_val, size_val, kind_val);
  CAMLlocal1(ba);
  WGPUBuffer buffer = (WGPUBuffer)Nativeint_val(buffer_val);
  size_t offset = Int64_val(offset_val);
  size_t size = Int64_val(size_val);
  int kind = Int_val(kind_val);

  void* ptr = wgpuBufferGetMappedRange(buffer, offset, size);
  if (ptr == NULL) {
    caml_failwith("wgpuBufferGetMappedRange returned NULL");
  }

  /* Create a bigarray that wraps the mapped memory */
  size_t elem_size = ba_element_size(kind);
  intnat dims[1] = { size / elem_size };
  ba = caml_ba_alloc(kind | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL, 1, ptr, dims);

  CAMLreturn(ba);
}

/* Get const mapped range as bigarray (for reading) */
CAMLprim value caml_wgpu_buffer_get_const_mapped_range_bigarray(value buffer_val, value offset_val, value size_val, value kind_val) {
  CAMLparam4(buffer_val, offset_val, size_val, kind_val);
  CAMLlocal1(ba);
  WGPUBuffer buffer = (WGPUBuffer)Nativeint_val(buffer_val);
  size_t offset = Int64_val(offset_val);
  size_t size = Int64_val(size_val);
  int kind = Int_val(kind_val);

  const void* ptr = wgpuBufferGetConstMappedRange(buffer, offset, size);
  if (ptr == NULL) {
    caml_failwith("wgpuBufferGetConstMappedRange returned NULL");
  }

  size_t elem_size = ba_element_size(kind);
  intnat dims[1] = { size / elem_size };
  ba = caml_ba_alloc(kind | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL, 1, (void*)ptr, dims);

  CAMLreturn(ba);
}

/* Write buffer from bigarray */
CAMLprim value caml_wgpu_queue_write_buffer_bigarray(value queue_val, value buffer_val, value offset_val, value data_val) {
  CAMLparam4(queue_val, buffer_val, offset_val, data_val);
  WGPUQueue queue = (WGPUQueue)Nativeint_val(queue_val);
  WGPUBuffer buffer = (WGPUBuffer)Nativeint_val(buffer_val);
  uint64_t offset = Int64_val(offset_val);

  void* data = Caml_ba_data_val(data_val);
  size_t size = caml_ba_byte_size(Caml_ba_array_val(data_val));

  wgpuQueueWriteBuffer(queue, buffer, offset, data, size);
  CAMLreturn(Val_unit);
}

/* Create bind group layout with a single storage buffer entry */
CAMLprim value caml_wgpu_device_create_bind_group_layout_storage(value device_val, value label_val, value binding_val, value read_only_val) {
  CAMLparam4(device_val, label_val, binding_val, read_only_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  uint32_t binding = Int_val(binding_val);
  bool read_only = Bool_val(read_only_val);

  WGPUBindGroupLayoutEntry entry = {
    .binding = binding,
    .visibility = WGPUShaderStage_Compute,
    .buffer = {
      .type = read_only ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage,
      .hasDynamicOffset = false,
      .minBindingSize = 0,
    },
  };

  WGPUBindGroupLayoutDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .entryCount = 1,
    .entries = &entry,
  };

  WGPUBindGroupLayout layout = wgpuDeviceCreateBindGroupLayout(device, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)layout));
}

/* Create bind group with a single buffer entry */
CAMLprim value caml_wgpu_device_create_bind_group_buffer(value device_val, value label_val, value layout_val, value binding_val, value buffer_val, value offset_val, value size_val) {
  CAMLparam5(device_val, label_val, layout_val, binding_val, buffer_val);
  CAMLxparam2(offset_val, size_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  WGPUBindGroupLayout layout = (WGPUBindGroupLayout)Nativeint_val(layout_val);
  uint32_t binding = Int_val(binding_val);
  WGPUBuffer buffer = (WGPUBuffer)Nativeint_val(buffer_val);
  uint64_t offset = Int64_val(offset_val);
  uint64_t size = Int64_val(size_val);

  WGPUBindGroupEntry entry = {
    .binding = binding,
    .buffer = buffer,
    .offset = offset,
    .size = size,
  };

  WGPUBindGroupDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .layout = layout,
    .entryCount = 1,
    .entries = &entry,
  };

  WGPUBindGroup group = wgpuDeviceCreateBindGroup(device, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)group));
}

CAMLprim value caml_wgpu_device_create_bind_group_buffer_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_bind_group_buffer(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

/* Create a 2D texture with given dimensions, format, and usage */
CAMLprim value caml_wgpu_device_create_texture_2d(value device_val, value label_val, value width_val, value height_val, value format_val, value usage_val) {
  CAMLparam5(device_val, label_val, width_val, height_val, format_val);
  CAMLxparam1(usage_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  uint32_t width = Int_val(width_val);
  uint32_t height = Int_val(height_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUTextureUsage usage = Int_val(usage_val);

  WGPUTextureDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .usage = usage,
    .dimension = WGPUTextureDimension_2D,
    .size = { .width = width, .height = height, .depthOrArrayLayers = 1 },
    .format = format,
    .mipLevelCount = 1,
    .sampleCount = 1,
    .viewFormatCount = 0,
    .viewFormats = NULL,
  };

  WGPUTexture texture = wgpuDeviceCreateTexture(device, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)texture));
}

CAMLprim value caml_wgpu_device_create_texture_2d_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_texture_2d(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* Create texture view with configurable settings */
CAMLprim value caml_wgpu_texture_create_view_configurable(value texture_val, value label_val,
    value format_val, value dimension_val, value aspect_val,
    value base_mip_level_val, value mip_level_count_val,
    value base_array_layer_val, value array_layer_count_val) {
  CAMLparam5(texture_val, label_val, format_val, dimension_val, aspect_val);
  CAMLxparam4(base_mip_level_val, mip_level_count_val, base_array_layer_val, array_layer_count_val);
  WGPUTexture texture = (WGPUTexture)Nativeint_val(texture_val);
  const char* label = String_val(label_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUTextureViewDimension dimension = Int_val(dimension_val);
  WGPUTextureAspect aspect = Int_val(aspect_val);
  uint32_t base_mip_level = Int_val(base_mip_level_val);
  uint32_t mip_level_count = Int_val(mip_level_count_val);
  uint32_t base_array_layer = Int_val(base_array_layer_val);
  uint32_t array_layer_count = Int_val(array_layer_count_val);

  WGPUTextureViewDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .format = format,
    .dimension = dimension,
    .baseMipLevel = base_mip_level,
    .mipLevelCount = mip_level_count,
    .baseArrayLayer = base_array_layer,
    .arrayLayerCount = array_layer_count,
    .aspect = aspect,
  };

  WGPUTextureView view = wgpuTextureCreateView(texture, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)view));
}

CAMLprim value caml_wgpu_texture_create_view_configurable_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_texture_create_view_configurable(
    argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

/* Begin a render pass with a single color attachment with configurable load/store ops */
CAMLprim value caml_wgpu_command_encoder_begin_render_pass_configurable(
    value encoder_val, value label_val, value view_val,
    value load_op_val, value store_op_val,
    value r_val, value g_val, value b_val, value a_val) {
  CAMLparam5(encoder_val, label_val, view_val, load_op_val, store_op_val);
  CAMLxparam4(r_val, g_val, b_val, a_val);
  WGPUCommandEncoder encoder = (WGPUCommandEncoder)Nativeint_val(encoder_val);
  const char* label = String_val(label_val);
  WGPUTextureView view = (WGPUTextureView)Nativeint_val(view_val);
  WGPULoadOp load_op = Int_val(load_op_val);
  WGPUStoreOp store_op = Int_val(store_op_val);
  double r = Double_val(r_val);
  double g = Double_val(g_val);
  double b = Double_val(b_val);
  double a = Double_val(a_val);

  WGPURenderPassColorAttachment color_attachment = {
    .view = view,
    .depthSlice = WGPU_DEPTH_SLICE_UNDEFINED, /* Required for non-3D textures */
    .resolveTarget = NULL,
    .loadOp = load_op,
    .storeOp = store_op,
    .clearValue = { .r = r, .g = g, .b = b, .a = a },
  };

  WGPURenderPassDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .colorAttachmentCount = 1,
    .colorAttachments = &color_attachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)pass));
}

CAMLprim value caml_wgpu_command_encoder_begin_render_pass_configurable_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_command_encoder_begin_render_pass_configurable(
    argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

/* Create a render pipeline with full configuration */
CAMLprim value caml_wgpu_device_create_render_pipeline_full(
    value device_val, value label_val, value shader_val,
    value vs_entry_val, value fs_entry_val, value format_val,
    value topology_val, value front_face_val, value cull_mode_val,
    value blend_enabled_val,
    value color_src_factor_val, value color_dst_factor_val, value color_operation_val,
    value alpha_src_factor_val, value alpha_dst_factor_val, value alpha_operation_val,
    value write_mask_val) {
  CAMLparam5(device_val, label_val, shader_val, vs_entry_val, fs_entry_val);
  CAMLxparam5(format_val, topology_val, front_face_val, cull_mode_val, blend_enabled_val);
  CAMLxparam4(color_src_factor_val, color_dst_factor_val, color_operation_val, alpha_src_factor_val);
  CAMLxparam3(alpha_dst_factor_val, alpha_operation_val, write_mask_val);

  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  WGPUShaderModule shader = (WGPUShaderModule)Nativeint_val(shader_val);
  const char* vs_entry = String_val(vs_entry_val);
  const char* fs_entry = String_val(fs_entry_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUPrimitiveTopology topology = Int_val(topology_val);
  WGPUFrontFace front_face = Int_val(front_face_val);
  WGPUCullMode cull_mode = Int_val(cull_mode_val);
  bool blend_enabled = Bool_val(blend_enabled_val);
  WGPUBlendFactor color_src_factor = Int_val(color_src_factor_val);
  WGPUBlendFactor color_dst_factor = Int_val(color_dst_factor_val);
  WGPUBlendOperation color_operation = Int_val(color_operation_val);
  WGPUBlendFactor alpha_src_factor = Int_val(alpha_src_factor_val);
  WGPUBlendFactor alpha_dst_factor = Int_val(alpha_dst_factor_val);
  WGPUBlendOperation alpha_operation = Int_val(alpha_operation_val);
  WGPUColorWriteMask write_mask = Int_val(write_mask_val);

  /* Create an empty pipeline layout (no bind groups) */
  WGPUPipelineLayoutDescriptor layout_desc = {
    .label = { .data = "empty_layout", .length = 12 },
    .bindGroupLayoutCount = 0,
    .bindGroupLayouts = NULL,
  };
  WGPUPipelineLayout layout = wgpuDeviceCreatePipelineLayout(device, &layout_desc);

  /* Blend state (only used if blend_enabled) */
  WGPUBlendState blend_state = {
    .color = {
      .srcFactor = color_src_factor,
      .dstFactor = color_dst_factor,
      .operation = color_operation,
    },
    .alpha = {
      .srcFactor = alpha_src_factor,
      .dstFactor = alpha_dst_factor,
      .operation = alpha_operation,
    },
  };

  /* Color target state */
  WGPUColorTargetState color_target = {
    .format = format,
    .blend = blend_enabled ? &blend_state : NULL,
    .writeMask = write_mask,
  };

  /* Fragment state */
  WGPUFragmentState fragment = {
    .module = shader,
    .entryPoint = { .data = fs_entry, .length = strlen(fs_entry) },
    .constantCount = 0,
    .constants = NULL,
    .targetCount = 1,
    .targets = &color_target,
  };

  /* Render pipeline descriptor */
  WGPURenderPipelineDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .layout = layout,
    .vertex = {
      .module = shader,
      .entryPoint = { .data = vs_entry, .length = strlen(vs_entry) },
      .constantCount = 0,
      .constants = NULL,
      .bufferCount = 0,
      .buffers = NULL,
    },
    .primitive = {
      .topology = topology,
      .stripIndexFormat = WGPUIndexFormat_Undefined,
      .frontFace = front_face,
      .cullMode = cull_mode,
    },
    .depthStencil = NULL,
    .multisample = {
      .count = 1,
      .mask = 0xFFFFFFFF,
      .alphaToCoverageEnabled = false,
    },
    .fragment = &fragment,
  };

  WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(device, &desc);

  /* Release the pipeline layout (pipeline holds a reference) */
  wgpuPipelineLayoutRelease(layout);

  CAMLreturn(caml_copy_nativeint((intnat)pipeline));
}

CAMLprim value caml_wgpu_device_create_render_pipeline_full_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_render_pipeline_full(
    argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8],
    argv[9], argv[10], argv[11], argv[12], argv[13], argv[14], argv[15], argv[16]);
}

/* Create bind group layout with a single uniform buffer entry */
CAMLprim value caml_wgpu_device_create_bind_group_layout_uniform(value device_val, value label_val, value binding_val, value visibility_val) {
  CAMLparam4(device_val, label_val, binding_val, visibility_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  uint32_t binding = Int_val(binding_val);
  WGPUShaderStage visibility = Int_val(visibility_val);

  WGPUBindGroupLayoutEntry entry = {
    .binding = binding,
    .visibility = visibility,
    .buffer = {
      .type = WGPUBufferBindingType_Uniform,
      .hasDynamicOffset = false,
      .minBindingSize = 0,
    },
  };

  WGPUBindGroupLayoutDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .entryCount = 1,
    .entries = &entry,
  };

  WGPUBindGroupLayout layout = wgpuDeviceCreateBindGroupLayout(device, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)layout));
}

/* Create a render pipeline with an explicit pipeline layout */
CAMLprim value caml_wgpu_device_create_render_pipeline_with_layout(
    value device_val, value label_val, value shader_val,
    value vs_entry_val, value fs_entry_val, value format_val,
    value topology_val, value front_face_val, value cull_mode_val,
    value blend_enabled_val,
    value color_src_factor_val, value color_dst_factor_val, value color_operation_val,
    value alpha_src_factor_val, value alpha_dst_factor_val, value alpha_operation_val,
    value write_mask_val, value layout_val) {
  CAMLparam5(device_val, label_val, shader_val, vs_entry_val, fs_entry_val);
  CAMLxparam5(format_val, topology_val, front_face_val, cull_mode_val, blend_enabled_val);
  CAMLxparam4(color_src_factor_val, color_dst_factor_val, color_operation_val, alpha_src_factor_val);
  CAMLxparam4(alpha_dst_factor_val, alpha_operation_val, write_mask_val, layout_val);

  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char* label = String_val(label_val);
  WGPUShaderModule shader = (WGPUShaderModule)Nativeint_val(shader_val);
  const char* vs_entry = String_val(vs_entry_val);
  const char* fs_entry = String_val(fs_entry_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUPrimitiveTopology topology = Int_val(topology_val);
  WGPUFrontFace front_face = Int_val(front_face_val);
  WGPUCullMode cull_mode = Int_val(cull_mode_val);
  bool blend_enabled = Bool_val(blend_enabled_val);
  WGPUBlendFactor color_src_factor = Int_val(color_src_factor_val);
  WGPUBlendFactor color_dst_factor = Int_val(color_dst_factor_val);
  WGPUBlendOperation color_operation = Int_val(color_operation_val);
  WGPUBlendFactor alpha_src_factor = Int_val(alpha_src_factor_val);
  WGPUBlendFactor alpha_dst_factor = Int_val(alpha_dst_factor_val);
  WGPUBlendOperation alpha_operation = Int_val(alpha_operation_val);
  WGPUColorWriteMask write_mask = Int_val(write_mask_val);
  WGPUPipelineLayout layout = (WGPUPipelineLayout)Nativeint_val(layout_val);

  /* Blend state (only used if blend_enabled) */
  WGPUBlendState blend_state = {
    .color = {
      .srcFactor = color_src_factor,
      .dstFactor = color_dst_factor,
      .operation = color_operation,
    },
    .alpha = {
      .srcFactor = alpha_src_factor,
      .dstFactor = alpha_dst_factor,
      .operation = alpha_operation,
    },
  };

  /* Color target state */
  WGPUColorTargetState color_target = {
    .format = format,
    .blend = blend_enabled ? &blend_state : NULL,
    .writeMask = write_mask,
  };

  /* Fragment state */
  WGPUFragmentState fragment = {
    .module = shader,
    .entryPoint = { .data = fs_entry, .length = strlen(fs_entry) },
    .constantCount = 0,
    .constants = NULL,
    .targetCount = 1,
    .targets = &color_target,
  };

  /* Render pipeline descriptor */
  WGPURenderPipelineDescriptor desc = {
    .label = { .data = label, .length = caml_string_length(label_val) },
    .layout = layout,
    .vertex = {
      .module = shader,
      .entryPoint = { .data = vs_entry, .length = strlen(vs_entry) },
      .constantCount = 0,
      .constants = NULL,
      .bufferCount = 0,
      .buffers = NULL,
    },
    .primitive = {
      .topology = topology,
      .stripIndexFormat = WGPUIndexFormat_Undefined,
      .frontFace = front_face,
      .cullMode = cull_mode,
    },
    .depthStencil = NULL,
    .multisample = {
      .count = 1,
      .mask = 0xFFFFFFFF,
      .alphaToCoverageEnabled = false,
    },
    .fragment = &fragment,
  };

  WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(device, &desc);

  CAMLreturn(caml_copy_nativeint((intnat)pipeline));
}

CAMLprim value caml_wgpu_device_create_render_pipeline_with_layout_bytecode(value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_render_pipeline_with_layout(
    argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8],
    argv[9], argv[10], argv[11], argv[12], argv[13], argv[14], argv[15], argv[16], argv[17]);
}

/*
 * Create a render pipeline with vertex buffer layouts.
 *
 * vertex_buffer_layouts_val is an OCaml array where each element is a tuple:
 *   (step_mode: int, array_stride: int64, attributes: array)
 * and each attribute is a tuple:
 *   (format: int, offset: int64, shader_location: int)
 */
CAMLprim value caml_wgpu_device_create_render_pipeline_with_vertex_buffers(
    value device_val, value label_val, value shader_val, value vs_entry_val,
    value fs_entry_val, value format_val, value topology_val,
    value front_face_val, value cull_mode_val, value blend_enabled_val,
    value color_src_factor_val, value color_dst_factor_val,
    value color_operation_val, value alpha_src_factor_val,
    value alpha_dst_factor_val, value alpha_operation_val, value write_mask_val,
    value layout_opt_val, value vertex_buffer_layouts_val) {
  CAMLparam5(device_val, label_val, shader_val, vs_entry_val, fs_entry_val);
  CAMLxparam5(format_val, topology_val, front_face_val, cull_mode_val,
              blend_enabled_val);
  CAMLxparam5(color_src_factor_val, color_dst_factor_val, color_operation_val,
              alpha_src_factor_val, alpha_dst_factor_val);
  CAMLxparam4(alpha_operation_val, write_mask_val, layout_opt_val,
              vertex_buffer_layouts_val);

  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char *label = String_val(label_val);
  WGPUShaderModule shader = (WGPUShaderModule)Nativeint_val(shader_val);
  const char *vs_entry = String_val(vs_entry_val);
  const char *fs_entry = String_val(fs_entry_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUPrimitiveTopology topology = Int_val(topology_val);
  WGPUFrontFace front_face = Int_val(front_face_val);
  WGPUCullMode cull_mode = Int_val(cull_mode_val);
  bool blend_enabled = Bool_val(blend_enabled_val);
  WGPUBlendFactor color_src_factor = Int_val(color_src_factor_val);
  WGPUBlendFactor color_dst_factor = Int_val(color_dst_factor_val);
  WGPUBlendOperation color_operation = Int_val(color_operation_val);
  WGPUBlendFactor alpha_src_factor = Int_val(alpha_src_factor_val);
  WGPUBlendFactor alpha_dst_factor = Int_val(alpha_dst_factor_val);
  WGPUBlendOperation alpha_operation = Int_val(alpha_operation_val);
  WGPUColorWriteMask write_mask = Int_val(write_mask_val);

  /* Parse vertex buffer layouts from OCaml array */
  size_t buffer_count = Wosize_val(vertex_buffer_layouts_val);
  WGPUVertexBufferLayout *vertex_buffers = NULL;
  WGPUVertexAttribute **all_attributes = NULL;

  if (buffer_count > 0) {
    vertex_buffers = malloc(buffer_count * sizeof(WGPUVertexBufferLayout));
    all_attributes = malloc(buffer_count * sizeof(WGPUVertexAttribute *));

    for (size_t i = 0; i < buffer_count; i++) {
      value layout = Field(vertex_buffer_layouts_val, i);
      /* layout is (step_mode: int, array_stride: int64, attributes: array) */
      int step_mode = Int_val(Field(layout, 0));
      uint64_t array_stride = Int64_val(Field(layout, 1));
      value attributes_arr = Field(layout, 2);

      size_t attr_count = Wosize_val(attributes_arr);
      WGPUVertexAttribute *attributes =
          malloc(attr_count * sizeof(WGPUVertexAttribute));
      all_attributes[i] = attributes;

      for (size_t j = 0; j < attr_count; j++) {
        value attr = Field(attributes_arr, j);
        /* attr is (format: int, offset: int64, shader_location: int) */
        attributes[j].format = Int_val(Field(attr, 0));
        attributes[j].offset = Int64_val(Field(attr, 1));
        attributes[j].shaderLocation = Int_val(Field(attr, 2));
      }

      vertex_buffers[i].stepMode = step_mode;
      vertex_buffers[i].arrayStride = array_stride;
      vertex_buffers[i].attributeCount = attr_count;
      vertex_buffers[i].attributes = attributes;
    }
  }

  /* Handle optional pipeline layout */
  WGPUPipelineLayout layout;
  bool layout_created = false;
  if (Is_block(layout_opt_val) && Tag_val(layout_opt_val) == 0) {
    /* Some layout */
    layout = (WGPUPipelineLayout)Nativeint_val(Field(layout_opt_val, 0));
  } else {
    /* None - create empty layout */
    WGPUPipelineLayoutDescriptor layout_desc = {
        .label = {.data = "empty_layout", .length = 12},
        .bindGroupLayoutCount = 0,
        .bindGroupLayouts = NULL,
    };
    layout = wgpuDeviceCreatePipelineLayout(device, &layout_desc);
    layout_created = true;
  }

  /* Blend state (only used if blend_enabled) */
  WGPUBlendState blend_state = {
      .color =
          {
              .srcFactor = color_src_factor,
              .dstFactor = color_dst_factor,
              .operation = color_operation,
          },
      .alpha =
          {
              .srcFactor = alpha_src_factor,
              .dstFactor = alpha_dst_factor,
              .operation = alpha_operation,
          },
  };

  /* Color target state */
  WGPUColorTargetState color_target = {
      .format = format,
      .blend = blend_enabled ? &blend_state : NULL,
      .writeMask = write_mask,
  };

  /* Fragment state */
  WGPUFragmentState fragment = {
      .module = shader,
      .entryPoint = {.data = fs_entry, .length = strlen(fs_entry)},
      .constantCount = 0,
      .constants = NULL,
      .targetCount = 1,
      .targets = &color_target,
  };

  /* Render pipeline descriptor */
  WGPURenderPipelineDescriptor desc = {
      .label = {.data = label, .length = caml_string_length(label_val)},
      .layout = layout,
      .vertex =
          {
              .module = shader,
              .entryPoint = {.data = vs_entry, .length = strlen(vs_entry)},
              .constantCount = 0,
              .constants = NULL,
              .bufferCount = buffer_count,
              .buffers = vertex_buffers,
          },
      .primitive =
          {
              .topology = topology,
              .stripIndexFormat = WGPUIndexFormat_Undefined,
              .frontFace = front_face,
              .cullMode = cull_mode,
          },
      .depthStencil = NULL,
      .multisample =
          {
              .count = 1,
              .mask = 0xFFFFFFFF,
              .alphaToCoverageEnabled = false,
          },
      .fragment = &fragment,
  };

  WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(device, &desc);

  /* Cleanup */
  if (layout_created) {
    wgpuPipelineLayoutRelease(layout);
  }
  if (all_attributes != NULL) {
    for (size_t i = 0; i < buffer_count; i++) {
      free(all_attributes[i]);
    }
    free(all_attributes);
  }
  if (vertex_buffers != NULL) {
    free(vertex_buffers);
  }

  CAMLreturn(caml_copy_nativeint((intnat)pipeline));
}

CAMLprim value
caml_wgpu_device_create_render_pipeline_with_vertex_buffers_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_render_pipeline_with_vertex_buffers(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7],
      argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14],
      argv[15], argv[16], argv[17], argv[18]);
}

/*
 * Create a render pipeline with vertex buffer layouts and depth-stencil state.
 *
 * Same as device_create_render_pipeline_with_vertex_buffers but adds:
 * - depth_format_opt_val: int option (texture format for depth buffer)
 * - depth_write_enabled_val: bool (whether to write to depth buffer)
 * - depth_compare_val: int (comparison function)
 */
CAMLprim value caml_wgpu_device_create_render_pipeline_with_depth(
    value device_val, value label_val, value shader_val, value vs_entry_val,
    value fs_entry_val, value format_val, value topology_val,
    value front_face_val, value cull_mode_val, value blend_enabled_val,
    value color_src_factor_val, value color_dst_factor_val,
    value color_operation_val, value alpha_src_factor_val,
    value alpha_dst_factor_val, value alpha_operation_val, value write_mask_val,
    value layout_opt_val, value vertex_buffer_layouts_val,
    value depth_format_opt_val, value depth_write_enabled_val,
    value depth_compare_val) {
  CAMLparam5(device_val, label_val, shader_val, vs_entry_val, fs_entry_val);
  CAMLxparam5(format_val, topology_val, front_face_val, cull_mode_val,
              blend_enabled_val);
  CAMLxparam5(color_src_factor_val, color_dst_factor_val, color_operation_val,
              alpha_src_factor_val, alpha_dst_factor_val);
  CAMLxparam5(alpha_operation_val, write_mask_val, layout_opt_val,
              vertex_buffer_layouts_val, depth_format_opt_val);
  CAMLxparam2(depth_write_enabled_val, depth_compare_val);

  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  const char *label = String_val(label_val);
  WGPUShaderModule shader = (WGPUShaderModule)Nativeint_val(shader_val);
  const char *vs_entry = String_val(vs_entry_val);
  const char *fs_entry = String_val(fs_entry_val);
  WGPUTextureFormat format = Int_val(format_val);
  WGPUPrimitiveTopology topology = Int_val(topology_val);
  WGPUFrontFace front_face = Int_val(front_face_val);
  WGPUCullMode cull_mode = Int_val(cull_mode_val);
  bool blend_enabled = Bool_val(blend_enabled_val);
  WGPUBlendFactor color_src_factor = Int_val(color_src_factor_val);
  WGPUBlendFactor color_dst_factor = Int_val(color_dst_factor_val);
  WGPUBlendOperation color_operation = Int_val(color_operation_val);
  WGPUBlendFactor alpha_src_factor = Int_val(alpha_src_factor_val);
  WGPUBlendFactor alpha_dst_factor = Int_val(alpha_dst_factor_val);
  WGPUBlendOperation alpha_operation = Int_val(alpha_operation_val);
  WGPUColorWriteMask write_mask = Int_val(write_mask_val);

  /* Parse vertex buffer layouts from OCaml array */
  size_t buffer_count = Wosize_val(vertex_buffer_layouts_val);
  WGPUVertexBufferLayout *vertex_buffers = NULL;
  WGPUVertexAttribute **all_attributes = NULL;

  if (buffer_count > 0) {
    vertex_buffers = malloc(buffer_count * sizeof(WGPUVertexBufferLayout));
    all_attributes = malloc(buffer_count * sizeof(WGPUVertexAttribute *));

    for (size_t i = 0; i < buffer_count; i++) {
      value layout = Field(vertex_buffer_layouts_val, i);
      int step_mode = Int_val(Field(layout, 0));
      uint64_t array_stride = Int64_val(Field(layout, 1));
      value attributes_arr = Field(layout, 2);

      size_t attr_count = Wosize_val(attributes_arr);
      WGPUVertexAttribute *attributes =
          malloc(attr_count * sizeof(WGPUVertexAttribute));
      all_attributes[i] = attributes;

      for (size_t j = 0; j < attr_count; j++) {
        value attr = Field(attributes_arr, j);
        attributes[j].format = Int_val(Field(attr, 0));
        attributes[j].offset = Int64_val(Field(attr, 1));
        attributes[j].shaderLocation = Int_val(Field(attr, 2));
      }

      vertex_buffers[i].stepMode = step_mode;
      vertex_buffers[i].arrayStride = array_stride;
      vertex_buffers[i].attributeCount = attr_count;
      vertex_buffers[i].attributes = attributes;
    }
  }

  /* Handle optional pipeline layout */
  WGPUPipelineLayout layout;
  bool layout_created = false;
  if (Is_block(layout_opt_val) && Tag_val(layout_opt_val) == 0) {
    layout = (WGPUPipelineLayout)Nativeint_val(Field(layout_opt_val, 0));
  } else {
    WGPUPipelineLayoutDescriptor layout_desc = {
        .label = {.data = "empty_layout", .length = 12},
        .bindGroupLayoutCount = 0,
        .bindGroupLayouts = NULL,
    };
    layout = wgpuDeviceCreatePipelineLayout(device, &layout_desc);
    layout_created = true;
  }

  /* Blend state */
  WGPUBlendState blend_state = {
      .color =
          {
              .srcFactor = color_src_factor,
              .dstFactor = color_dst_factor,
              .operation = color_operation,
          },
      .alpha =
          {
              .srcFactor = alpha_src_factor,
              .dstFactor = alpha_dst_factor,
              .operation = alpha_operation,
          },
  };

  /* Color target state */
  WGPUColorTargetState color_target = {
      .format = format,
      .blend = blend_enabled ? &blend_state : NULL,
      .writeMask = write_mask,
  };

  /* Fragment state */
  WGPUFragmentState fragment = {
      .module = shader,
      .entryPoint = {.data = fs_entry, .length = strlen(fs_entry)},
      .constantCount = 0,
      .constants = NULL,
      .targetCount = 1,
      .targets = &color_target,
  };

  /* Depth-stencil state (optional) */
  WGPUDepthStencilState depth_stencil_state;
  WGPUDepthStencilState *depth_stencil_ptr = NULL;

  if (Is_block(depth_format_opt_val) && Tag_val(depth_format_opt_val) == 0) {
    /* Some depth_format */
    WGPUTextureFormat depth_format = Int_val(Field(depth_format_opt_val, 0));
    bool depth_write_enabled = Bool_val(depth_write_enabled_val);
    WGPUCompareFunction depth_compare = Int_val(depth_compare_val);

    depth_stencil_state = (WGPUDepthStencilState){
        .format = depth_format,
        .depthWriteEnabled = depth_write_enabled ? WGPUOptionalBool_True
                                                 : WGPUOptionalBool_False,
        .depthCompare = depth_compare,
        .stencilFront =
            {
                .compare = WGPUCompareFunction_Always,
                .failOp = WGPUStencilOperation_Keep,
                .depthFailOp = WGPUStencilOperation_Keep,
                .passOp = WGPUStencilOperation_Keep,
            },
        .stencilBack =
            {
                .compare = WGPUCompareFunction_Always,
                .failOp = WGPUStencilOperation_Keep,
                .depthFailOp = WGPUStencilOperation_Keep,
                .passOp = WGPUStencilOperation_Keep,
            },
        .stencilReadMask = 0xFFFFFFFF,
        .stencilWriteMask = 0xFFFFFFFF,
        .depthBias = 0,
        .depthBiasSlopeScale = 0.0f,
        .depthBiasClamp = 0.0f,
    };
    depth_stencil_ptr = &depth_stencil_state;
  }

  /* Render pipeline descriptor */
  WGPURenderPipelineDescriptor desc = {
      .label = {.data = label, .length = caml_string_length(label_val)},
      .layout = layout,
      .vertex =
          {
              .module = shader,
              .entryPoint = {.data = vs_entry, .length = strlen(vs_entry)},
              .constantCount = 0,
              .constants = NULL,
              .bufferCount = buffer_count,
              .buffers = vertex_buffers,
          },
      .primitive =
          {
              .topology = topology,
              .stripIndexFormat = WGPUIndexFormat_Undefined,
              .frontFace = front_face,
              .cullMode = cull_mode,
          },
      .depthStencil = depth_stencil_ptr,
      .multisample =
          {
              .count = 1,
              .mask = 0xFFFFFFFF,
              .alphaToCoverageEnabled = false,
          },
      .fragment = &fragment,
  };

  WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(device, &desc);

  /* Cleanup */
  if (layout_created) {
    wgpuPipelineLayoutRelease(layout);
  }
  if (all_attributes != NULL) {
    for (size_t i = 0; i < buffer_count; i++) {
      free(all_attributes[i]);
    }
    free(all_attributes);
  }
  if (vertex_buffers != NULL) {
    free(vertex_buffers);
  }

  CAMLreturn(caml_copy_nativeint((intnat)pipeline));
}

CAMLprim value caml_wgpu_device_create_render_pipeline_with_depth_bytecode(
    value *argv, int argn) {
  (void)argn;
  return caml_wgpu_device_create_render_pipeline_with_depth(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7],
      argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14],
      argv[15], argv[16], argv[17], argv[18], argv[19], argv[20], argv[21]);
}

/*
 * Begin a render pass with a single color attachment and optional depth
 * attachment.
 *
 * depth_view_opt_val: nativeint option (texture view for depth buffer)
 * depth_load_op_val: int (load op for depth)
 * depth_store_op_val: int (store op for depth)
 * depth_clear_value_val: float (clear value for depth)
 */
CAMLprim value caml_wgpu_command_encoder_begin_render_pass_with_depth(
    value encoder_val, value label_val, value view_val, value load_op_val,
    value store_op_val, value r_val, value g_val, value b_val, value a_val,
    value depth_view_opt_val, value depth_load_op_val, value depth_store_op_val,
    value depth_clear_value_val) {
  CAMLparam5(encoder_val, label_val, view_val, load_op_val, store_op_val);
  CAMLxparam5(r_val, g_val, b_val, a_val, depth_view_opt_val);
  CAMLxparam3(depth_load_op_val, depth_store_op_val, depth_clear_value_val);

  WGPUCommandEncoder encoder = (WGPUCommandEncoder)Nativeint_val(encoder_val);
  const char *label = String_val(label_val);
  WGPUTextureView view = (WGPUTextureView)Nativeint_val(view_val);
  WGPULoadOp load_op = Int_val(load_op_val);
  WGPUStoreOp store_op = Int_val(store_op_val);
  double r = Double_val(r_val);
  double g = Double_val(g_val);
  double b = Double_val(b_val);
  double a = Double_val(a_val);

  WGPURenderPassColorAttachment color_attachment = {
      .view = view,
      .depthSlice = WGPU_DEPTH_SLICE_UNDEFINED,
      .resolveTarget = NULL,
      .loadOp = load_op,
      .storeOp = store_op,
      .clearValue = {.r = r, .g = g, .b = b, .a = a},
  };

  /* Depth-stencil attachment (optional) */
  WGPURenderPassDepthStencilAttachment depth_attachment;
  WGPURenderPassDepthStencilAttachment *depth_attachment_ptr = NULL;

  if (Is_block(depth_view_opt_val) && Tag_val(depth_view_opt_val) == 0) {
    /* Some depth_view */
    WGPUTextureView depth_view =
        (WGPUTextureView)Nativeint_val(Field(depth_view_opt_val, 0));
    WGPULoadOp depth_load_op = Int_val(depth_load_op_val);
    WGPUStoreOp depth_store_op = Int_val(depth_store_op_val);
    double depth_clear_value = Double_val(depth_clear_value_val);

    depth_attachment = (WGPURenderPassDepthStencilAttachment){
        .view = depth_view,
        .depthLoadOp = depth_load_op,
        .depthStoreOp = depth_store_op,
        .depthClearValue = (float)depth_clear_value,
        .depthReadOnly = false,
        .stencilLoadOp = WGPULoadOp_Undefined,
        .stencilStoreOp = WGPUStoreOp_Undefined,
        .stencilClearValue = 0,
        .stencilReadOnly = true,
    };
    depth_attachment_ptr = &depth_attachment;
  }

  WGPURenderPassDescriptor desc = {
      .label = {.data = label, .length = caml_string_length(label_val)},
      .colorAttachmentCount = 1,
      .colorAttachments = &color_attachment,
      .depthStencilAttachment = depth_attachment_ptr,
      .occlusionQuerySet = NULL,
      .timestampWrites = NULL,
  };

  WGPURenderPassEncoder pass =
      wgpuCommandEncoderBeginRenderPass(encoder, &desc);
  CAMLreturn(caml_copy_nativeint((intnat)pass));
}

CAMLprim value
caml_wgpu_command_encoder_begin_render_pass_with_depth_bytecode(value *argv,
                                                                int argn) {
  (void)argn;
  return caml_wgpu_command_encoder_begin_render_pass_with_depth(
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7],
      argv[8], argv[9], argv[10], argv[11], argv[12]);
}

/* Write texture from bigarray */
CAMLprim value caml_wgpu_queue_write_texture_bigarray(
    value queue_val, value destination_val, value data_layout_val,
    value write_size_val, value data_val) {
  CAMLparam5(queue_val, destination_val, data_layout_val, write_size_val, data_val);
  WGPUQueue queue = (WGPUQueue)Nativeint_val(queue_val);
  WGPUTexelCopyTextureInfo *destination =
      (WGPUTexelCopyTextureInfo *)Nativeint_val(destination_val);
  WGPUTexelCopyBufferLayout *data_layout =
      (WGPUTexelCopyBufferLayout *)Nativeint_val(data_layout_val);
  WGPUExtent3D *write_size = (WGPUExtent3D *)Nativeint_val(write_size_val);

  void *data = Caml_ba_data_val(data_val);
  size_t data_size = caml_ba_byte_size(Caml_ba_array_val(data_val));

  wgpuQueueWriteTexture(queue, destination, data, data_size, data_layout,
                        write_size);
  CAMLreturn(Val_unit);
}

