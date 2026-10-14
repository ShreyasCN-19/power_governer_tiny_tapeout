## How it works

PwrGov-X is a telemetry-driven power governor IP designed in Verilog. It monitors system activity and temperature, classifies workload, predicts workload trends, and generates power-management control signals.

The design uses a telemetry monitor, window controller, feature extractor, workload classifier, workload predictor, FSM controller, and control signal generator.

The Tiny Tapeout interface uses:
- `ui_in[0]`: Enable request
- `ui_in[1]`: Activity input
- `ui_in[4:2]`: Temperature input
- `uo_out[0]`: Performance enable
- `uo_out[1]`: Throttle active
- `uo_out[3:2]`: Control level
- `uo_out[5:4]`: Workload class
- `uo_out[7:6]`: Operating mode

Thermal hysteresis helps prevent rapid switching between throttled and normal operation. The unused bidirectional outputs are held at zero.

## How to test

The project includes a Verilog testbench wrapper in `test/tb.v` and a Cocotb integration test in `test/test.py`.

To run the tests locally, install Icarus Verilog and the Python packages listed in `test/requirements.txt`, then run:

```bash
cd test
make clean
make
python -m cocotb_tools.check_results results.xml
```

The automated test checks reset behavior, output values, thermal throttling and hysteresis, and disabling the enable request. GitHub Actions runs the test automatically when changes are pushed to the repository.

## External hardware

The design targets the Tiny Tapeout SKY130 digital design flow. It is intended to be synthesized and physically implemented using the SkyWater SKY130 process design kit. No external hardware peripheral is required for the RTL simulation.
