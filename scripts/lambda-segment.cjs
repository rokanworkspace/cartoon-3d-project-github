// Render one frame-range segment of BridgeShort on Lambda with exactly ONE
// chunk (framesPerLambda = segment length), so the launcher only ever invokes
// a single child function — used to probe per-frame cost and to render the
// full video as sequential segments on throttling-prone new AWS accounts.
// Usage: node scripts/lambda-segment.cjs <startFrame> <endFrame> <outFile>
require("dotenv").config();
const fs = require("fs");
const { renderMediaOnLambda, getRenderProgress } = require("@remotion/lambda-client");
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { Readable } = require("stream");
const { pipeline } = require("stream/promises");

const REGION = "ap-southeast-2";
const FUNCTION = "remotion-render-4-0-541-mem3008mb-disk2048mb-900sec";
const SERVE_URL =
  "https://remotionlambda-apsoutheast2-konj2rbwrp.s3.ap-southeast-2.amazonaws.com/sites/bridge-short/index.html";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const [start, end, outFile] = [
    parseInt(process.argv[2], 10),
    parseInt(process.argv[3], 10),
    process.argv[4],
  ];
  const frames = end - start + 1;
  const t0 = Date.now();
  const { renderId, bucketName } = await renderMediaOnLambda({
    region: REGION,
    functionName: FUNCTION,
    serveUrl: SERVE_URL,
    composition: "BridgeShort",
    codec: "h264",
    imageFormat: "jpeg",
    frameRange: [start, end],
    framesPerLambda: frames,
    timeoutInMilliseconds: 240000,
    privacy: "public",
    overwrite: true,
  });
  console.log(`segment ${start}-${end} renderId=${renderId} bucket=${bucketName}`);
  let lastFrames = -1;
  for (;;) {
    const p = await getRenderProgress({
      region: REGION,
      functionName: FUNCTION,
      bucketName,
      renderId,
    });
    const elapsed = ((Date.now() - t0) / 1000).toFixed(0);
    if (p.framesRendered !== lastFrames) {
      console.log(
        `[${elapsed}s] framesRendered=${p.framesRendered}/${frames} encoded=${p.framesEncoded} done=${p.done} errors=${p.errors.length}`
      );
      lastFrames = p.framesRendered;
    }
    if (p.errors.length) {
      console.log("ERROR:", JSON.stringify(p.errors[0]).slice(0, 500));
      process.exit(2);
    }
    if (p.done) {
      console.log(`[${elapsed}s] DONE outputFile=${p.outputFile}`);
      const s3 = new S3Client({ region: REGION });
      const key = p.outputFile.replace(`https://s3.ap-southeast-2.amazonaws.com/${bucketName}/`, "");
      const obj = await s3.send(new GetObjectCommand({ Bucket: bucketName, Key: key }));
      await pipeline(obj.Body, fs.createWriteStream(outFile));
      console.log(`[${elapsed}s] downloaded -> ${outFile}`);
      break;
    }
    await sleep(10000);
  }
})().catch((e) => {
  console.log("SEGMENT FAIL:", e.name, e.message.slice(0, 400));
  process.exit(1);
});
