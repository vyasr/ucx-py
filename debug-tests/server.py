import argparse
import asyncio
import os

from distributed.comm.utils import to_frames
from distributed.protocol import to_serialize

import cloudpickle
import pytest
import ucp
from debug_utils import ITERATIONS, get_object, set_rmm, start_process, total_nvlink_transfer
from utils import recv, send

cmd = "nvidia-smi nvlink --setcontrol 0bz"  # Get output in bytes
# subprocess.check_call(cmd, shell=True)

pynvml = pytest.importorskip("pynvml", reason="PYNVML not installed")


async def get_ep(name, port):
    addr = ucp.get_address()
    ep = await ucp.create_endpoint(addr, port)
    return ep


def server(env, port, func, verbose):
    # create listener receiver
    # write cudf object
    # confirm message is sent correctly

    os.environ.update(env)

    async def f(listener_port):
        # coroutine shows up when the client asks
        # to connect
        set_rmm()

        async def write(ep):

            print("CREATING CUDA OBJECT IN SERVER...")
            cuda_obj_generator = cloudpickle.loads(func)
            cuda_obj = cuda_obj_generator()
            msg = {"data": to_serialize(cuda_obj)}
            frames = await to_frames(msg, serializers=("cuda", "dask", "pickle"))
            while True:
                for i in range(ITERATIONS):
                    print("ITER: ", i)
                    # Send meta data
                    await send(ep, frames)

                    frames, msg = await recv(ep)

                print("CONFIRM RECEIPT")
                await ep.close()
                break
            # lf.close()
            del msg
            del frames

        lf = ucp.create_listener(write, port=listener_port)
        try:
            while not lf.closed():
                await asyncio.sleep(0.1)
        except ucp.UCXCloseError:
            pass

    loop = asyncio.get_event_loop()
    while True:
        loop.run_until_complete(f(port))


def parse_args():
    parser = argparse.ArgumentParser(description="Tester server process")
    parser.add_argument(
        "-o",
        "--object_type",
        default="numpy",
        choices=["numpy", "cupy", "cudf"],
        help="In-memory array type.",
    )
    parser.add_argument(
        "-c",
        "--cpu-affinity",
        metavar="N",
        default=-1,
        type=int,
        help="CPU affinity (default -1: not set).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        default=False,
        action="store_true",
        help="Print timings per iteration.",
    )

    args = parser.parse_args()
    return args


def main():
    args = parse_args()

    start_process(args, server)


if __name__ == "__main__":
    main()
