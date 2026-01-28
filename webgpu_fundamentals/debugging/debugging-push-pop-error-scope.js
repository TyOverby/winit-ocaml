async function main() {
  const adapter = await navigator.gpu?.requestAdapter();
  const device = await adapter?.requestDevice();
  if (!device) {
    fail('need a browser that supports WebGPU');
    return;
  }

  device.addEventListener('uncapturederror', event => {
    log('uncaptured error:', event.error.message);
  });

  device.pushErrorScope('validation');
  device.createShaderModule({
    code: /* wgsl */ `
      this shader won't compile
    `,
  });
  const error = await device.popErrorScope();
  if (error) {
    log('captured error:', error.message);
  }

  device.createShaderModule({
    code: /* wgsl */ `
      also, this shader won't compile
    `,
  });

  device.queue.submit([]);
  log('--done--');
}

function fail(msg) {
  // eslint-disable-next-line no-alert
  alert(msg);
}

function log(...args) {
  const elem = document.createElement('pre');
  elem.textContent = args.join(' ');
  document.body.appendChild(elem);
}

main();
