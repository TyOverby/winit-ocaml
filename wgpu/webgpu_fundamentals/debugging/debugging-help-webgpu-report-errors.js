async function main() {
  const adapter = await navigator.gpu?.requestAdapter();
  const device = await adapter?.requestDevice();
  if (!device) {
    fail('need a browser that supports WebGPU');
    return;
  }

  device.addEventListener('uncapturederror', event => {
    log(event.error.message);
  });

  device.createShaderModule({
    code: /* wgsl */ `
      this shader won't compile
    `,
  });

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
