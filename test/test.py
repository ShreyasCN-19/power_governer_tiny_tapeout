
# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


@cocotb.test()
async def test_pwrgovx(dut):
    dut._log.info("Starting PwrGov-X integration test")

    # 10 ns clock period = 100 MHz
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    for _ in range(2):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Unused bidirectional pins must remain low and inputs.
    assert int(dut.uio_out.value) == 0, "uio_out must remain zero"
    assert int(dut.uio_oe.value) == 0, "uio_oe must remain zero"

    # After reset, enabled low workload should start in low-power mode.
    assert ((int(dut.uo_out.value) >> 6) & 0b11) == 0, (
        "Expected low-power mode after reset"
    )
    # Request thermal throttling: temperature code 6, enable request = 1.
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00011001

   # Allow the gate-level design several cycles to respond.
   for _ in range(3):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    mode = (int(dut.uo_out.value) >> 6) & 0b11
    throttle_active = (int(dut.uo_out.value) >> 1) & 1
    control_level = (int(dut.uo_out.value) >> 2) & 0b11

    assert mode == 0b10, f"Expected throttled mode 10, got {mode:02b}"
    assert throttle_active == 1, "Expected throttle_active to be asserted"
    assert control_level == 0b01, (
        f"Expected control level 01, got {control_level:02b}"
    )

    # Temperature 5 must retain the previous throttle state.
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00010101
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert ((int(dut.uo_out.value) >> 6) & 0b11) == 0b10, (
        "Throttle should remain active at temperature code 5"
    )
    assert ((int(dut.uo_out.value) >> 1) & 1) == 1, (
        "Throttle output should remain asserted at temperature code 5"
    )

    # Temperature 4 releases thermal throttling. The workload class
    # may determine whether the resulting mode is low-power or normal.
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0b00010001
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert ((int(dut.uo_out.value) >> 1) & 1) == 0, (
        "Throttle should release at temperature code 4"
    )

    # Disable the request; mode and control outputs must return to safe values.
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert ((int(dut.uo_out.value) >> 6) & 0b11) == 0, (
        "Expected low-power mode when enable request is disabled"
    )
    assert (int(dut.uo_out.value) & 0b11) == 0, (
        "Performance and throttle outputs should be low when disabled"
    )

    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0

    dut._log.info("PwrGov-X integration test passed")
