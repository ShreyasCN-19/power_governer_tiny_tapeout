
# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


@cocotb.test()
async def test_pwrgovx(dut):
    dut._log.info("Starting PwrGov-X integration test")

    # Start 100 MHz clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Initialize inputs
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    # Reset
    for _ in range(2):
        await RisingEdge(dut.clk)

    await Timer(1, unit="ns")
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Check unused bidirectional pins
    assert int(dut.uio_out.value) == 0, "uio_out must remain zero"
    assert int(dut.uio_oe.value) == 0, "uio_oe must remain zero"

    # Check initial low-power mode
    mode = (int(dut.uo_out.value) >> 6) & 0b11
    assert mode == 0b00, (
        f"Expected low-power mode 00 after reset, got {mode:02b}"
    )

    # Request thermal throttling at temperature code 6
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00011001

    # Allow the design three clock cycles to respond
    for _ in range(3):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    mode = (int(dut.uo_out.value) >> 6) & 0b11
    throttle_active = (int(dut.uo_out.value) >> 1) & 1
    control_level = (int(dut.uo_out.value) >> 2) & 0b11

    assert mode == 0b10, (
        f"Expected throttled mode 10, got {mode:02b}"
    )
    assert throttle_active == 1, (
        "Expected throttle_active to be asserted"
    )
    assert control_level == 0b01, (
        f"Expected control level 01, got {control_level:02b}"
    )

    # Temperature code 5: throttle must remain active
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00010101

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    mode = (int(dut.uo_out.value) >> 6) & 0b11
    throttle_active = (int(dut.uo_out.value) >> 1) & 1

    assert mode == 0b10, (
        f"Throttle should remain active at temperature 5, got {mode:02b}"
    )
    assert throttle_active == 1, (
        "Throttle output should remain asserted at temperature 5"
    )

   
    # Temperature code 4: throttle must release
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00010001

    # Give the gate-level sequential and combinational paths time to settle.
    for _ in range(2):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    throttle_active = (int(dut.uo_out.value) >> 1) & 1

    assert throttle_active == 0, (
        "Throttle should release at temperature code 4"
    )


    # Disable the enable request
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    mode = (int(dut.uo_out.value) >> 6) & 0b11
    low_outputs = int(dut.uo_out.value) & 0b11

    assert mode == 0b00, (
        f"Expected low-power mode when disabled, got {mode:02b}"
    )
    assert low_outputs == 0, (
        "Performance and throttle outputs should be low when disabled"
    )

    # Check unused bidirectional pins again
    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0

    dut._log.info("PwrGov-X integration test passed")
