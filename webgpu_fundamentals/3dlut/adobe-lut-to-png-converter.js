import * as lutParser from './resources/js/lut-reader.js';
import * as dragAndDrop from './resources/js/drag-and-drop.js';

let name = 'untitled';

function drawColorCubeImage(ctx, size) {
  const canvas = ctx.canvas;
  canvas.width = size * size;
  canvas.height = size;

  for (let zz = 0; zz < size; ++zz) {
    for (let yy = 0; yy < size; ++yy) {
      for (let xx = 0; xx < size; ++xx) {
        const r = Math.floor(xx / (size - 1) * 255);
        const g = Math.floor(yy / (size - 1) * 255);
        const b = Math.floor(zz / (size - 1) * 255);
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(zz * size + xx, yy, 1, 1);
      }
    }
  }
}

function drawLutToCanvas({size, data}, ctx) {
  ctx.canvas.width = size * size;
  ctx.canvas.height = size;
  const imgData = new ImageData(size * size, size);
  imgData.data.set(data);
  ctx.putImageData(imgData, 0, 0);
}

function main() {
  const canvas = document.querySelector('#c');
  const ctx = canvas.getContext('2d');
  drawColorCubeImage(ctx, 16);

  dragAndDrop.setup({msg: 'Drop LUT File here'});
  dragAndDrop.onDropFile(readLUTFile);

  function ext(s) {
    const period = s.lastIndexOf('.');
    return s.substr(period + 1);
  }

  function readLUTFile(file) {
    const reader = new FileReader();
    reader.onload = (e) => {
      const type = ext(file.name);
      const lut = lutParser.lutTo2D3Drgba8(lutParser.parse(e.target.result, type));
      drawLutToCanvas(lut, ctx);
      name = `${file.name || lut.name || 'untitled'}`;
      document.querySelector('#result').textContent = `loaded: ${name} size: ${lut.size}`;
    };

    reader.readAsText(file);
  }

  const saveData = (function() {
    const a = document.createElement('a');
    document.body.appendChild(a);
    a.style.display = 'none';
    return function saveData(blob, fileName) {
      const url = window.URL.createObjectURL(blob);
      a.href = url;
      a.download = fileName;
      a.click();
    };
  }());

  document.querySelector('button').addEventListener('click', () => {
    canvas.toBlob((blob) => {
      saveData(blob, `${name}-s${canvas.height}.png`);
    });
  });
}

main();
