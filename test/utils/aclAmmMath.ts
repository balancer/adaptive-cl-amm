import { BigNumberish } from 'ethers';
import { bn, fp, fpDivDown, fromFp, toFp } from '@balancer-labs/v3-helpers/src/numbers';

export function calculateSqrtQ0(
  currentTime: number,
  startSqrtQ0Fp: BigNumberish,
  endSqrtQ0Fp: BigNumberish,
  startTime: number,
  endTime: number
): bigint {
  if (currentTime < startTime) {
    return bn(startSqrtQ0Fp);
  } else if (currentTime >= endTime) {
    return bn(endSqrtQ0Fp);
  }

  const exponent = fromFp(fpDivDown(fp(currentTime - startTime), fp(endTime - startTime)));

  console.log('exponent', exponent);

  const base = fromFp(fpDivDown(endSqrtQ0Fp, startSqrtQ0Fp));

  console.log('base', base);
  console.log('base.pow(exponent)', base.pow(exponent));

  return fp(fromFp(startSqrtQ0Fp).mul(base.pow(exponent)));
}
