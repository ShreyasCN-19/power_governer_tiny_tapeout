`timescale 1ns / 1ps
`default_nettype none

module tt_um_pwrgovx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe
);

    wire rst;
    wire enable;
    wire activity;
    wire [2:0] temp_code;

    assign rst       = ~rst_n;
    assign enable    = ena & ui_in[0];
    assign activity  = ui_in[1];
    assign temp_code = ui_in[4:2];

    wire [4:0] active_count;
    wire [4:0] idle_count;
    wire [4:0] total_count;
    wire window_done;

    wire [4:0] activity_metric;
    wire feature_valid;

    wire [1:0] workload_class;
    wire class_valid;
    wire [1:0] workload_trend;

    wire [1:0] mode;
    wire throttle_request;
    wire perf_enable;
    wire throttle_active;
    wire [1:0] control_level;

    telemetry_monitor u_telemetry_monitor (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .activity(activity),
        .clear_window(window_done),
        .active_count(active_count),
        .idle_count(idle_count),
        .total_count(total_count)
    );

    window_controller u_window_controller (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .window_done(window_done)
    );

    feature_extractor u_feature_extractor (
        .clk(clk),
        .rst(rst),
        .window_done(window_done),
        .active_count(active_count),
        .idle_count(idle_count),
        .total_count(total_count),
        .activity_metric(activity_metric),
        .feature_valid(feature_valid)
    );

    workload_classifier u_workload_classifier (
        .clk(clk),
        .rst(rst),
        .feature_valid(feature_valid),
        .activity_metric(activity_metric),
        .workload_class(workload_class),
        .class_valid(class_valid)
    );

    workload_predictor u_workload_predictor (
        .clk(clk),
        .rst(rst),
        .class_valid(class_valid),
        .workload_class(workload_class),
        .workload_trend(workload_trend)
    );

    pwrgov_fsm u_pwrgov_fsm (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .temp_code(temp_code),
        .workload_class(workload_class),
        .workload_trend(workload_trend),
        .mode(mode),
        .throttle_request(throttle_request)
    );

    control_signal_generator u_control_signal_generator (
        .rst(rst),
        .enable(enable),
        .mode(mode),
        .throttle_request(throttle_request),
        .perf_enable(perf_enable),
        .throttle_active(throttle_active),
        .control_level(control_level)
    );

    assign uo_out[0]   = perf_enable;
    assign uo_out[1]   = throttle_active;
    assign uo_out[3:2] = control_level;
    assign uo_out[5:4] = workload_class;
    assign uo_out[7:6] = mode;

    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

    wire unused_inputs;
    assign unused_inputs = ^{uio_in, ui_in[7:5]};

endmodule


module telemetry_monitor (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire activity,
    input wire clear_window,
    output reg [4:0] active_count,
    output reg [4:0] idle_count,
    output reg [4:0] total_count
);

    always @(posedge clk) begin
        if (rst) begin
            active_count <= 5'd0;
            idle_count   <= 5'd0;
            total_count  <= 5'd0;
        end
        else if (clear_window) begin
            if (enable) begin
                total_count <= 5'd1;

                if (activity) begin
                    active_count <= 5'd1;
                    idle_count   <= 5'd0;
                end
                else begin
                    active_count <= 5'd0;
                    idle_count   <= 5'd1;
                end
            end
            else begin
                active_count <= 5'd0;
                idle_count   <= 5'd0;
                total_count  <= 5'd0;
            end
        end
        else if (enable) begin
            total_count <= total_count + 1'b1;

            if (activity)
                active_count <= active_count + 1'b1;
            else
                idle_count <= idle_count + 1'b1;
        end
    end

endmodule


module window_controller (
    input wire clk,
    input wire rst,
    input wire enable,
    output reg window_done
);

    reg [3:0] window_count;

    always @(posedge clk) begin
        if (rst) begin
            window_count <= 4'd0;
            window_done  <= 1'b0;
        end
        else begin
            window_done <= 1'b0;

            if (enable) begin
                if (window_count == 4'd15) begin
                    window_count <= 4'd0;
                    window_done  <= 1'b1;
                end
                else begin
                    window_count <= window_count + 1'b1;
                end
            end
        end
    end

endmodule


module feature_extractor (
    input wire clk,
    input wire rst,
    input wire window_done,
    input wire [4:0] active_count,
    input wire [4:0] idle_count,
    input wire [4:0] total_count,
    output reg [4:0] activity_metric,
    output reg feature_valid
);

    always @(posedge clk) begin
        if (rst) begin
            activity_metric <= 5'd0;
            feature_valid   <= 1'b0;
        end
        else begin
            feature_valid <= 1'b0;

            if (window_done) begin
                activity_metric <= active_count;
                feature_valid   <= 1'b1;
            end
        end
    end

endmodule


module workload_classifier (
    input wire clk,
    input wire rst,
    input wire feature_valid,
    input wire [4:0] activity_metric,
    output reg [1:0] workload_class,
    output reg class_valid
);

    always @(posedge clk) begin
        if (rst) begin
            workload_class <= 2'b00;
            class_valid    <= 1'b0;
        end
        else begin
            class_valid <= 1'b0;

            if (feature_valid) begin
                if (activity_metric <= 5'd3)
                    workload_class <= 2'b00;
                else if (activity_metric <= 5'd9)
                    workload_class <= 2'b01;
                else
                    workload_class <= 2'b10;

                class_valid <= 1'b1;
            end
        end
    end

endmodule


module pwrgov_fsm (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire [2:0] temp_code,
    input wire [1:0] workload_class,
    input wire [1:0] workload_trend,
    output reg [1:0] mode,
    output reg throttle_request
);

    localparam MODE_LOW_POWER = 2'b00;
    localparam MODE_NORMAL = 2'b01;
    localparam MODE_THROTTLED = 2'b10;

    localparam WORKLOAD_LOW = 2'b00;
    localparam TREND_RISING = 2'b01;

    reg thermal_latched;

    always @(posedge clk) begin
        if (rst)
            thermal_latched <= 1'b0;
        else if (!enable)
            thermal_latched <= 1'b0;
        else if (temp_code >= 3'd6)
            thermal_latched <= 1'b1;
        else if (temp_code <= 3'd4)
            thermal_latched <= 1'b0;
    end

    always @(*) begin
        mode = MODE_LOW_POWER;
        throttle_request = 1'b0;

        if (!enable) begin
            mode = MODE_LOW_POWER;
        end
        else if (thermal_latched) begin
            mode = MODE_THROTTLED;
            throttle_request = 1'b1;
        end
        else if ((workload_class == WORKLOAD_LOW) &&
                 (workload_trend != TREND_RISING)) begin
            mode = MODE_LOW_POWER;
        end
        else begin
            mode = MODE_NORMAL;
        end
    end

endmodule


module control_signal_generator (
    input wire rst,
    input wire enable,
    input wire [1:0] mode,
    input wire throttle_request,
    output reg perf_enable,
    output reg throttle_active,
    output reg [1:0] control_level
);

    localparam MODE_LOW_POWER = 2'b00;
    localparam MODE_NORMAL = 2'b01;
    localparam MODE_THROTTLED = 2'b10;

    always @(*) begin
        perf_enable = 1'b0;
        throttle_active = 1'b0;
        control_level = 2'b00;

        if (!rst && enable) begin
            case (mode)
                MODE_LOW_POWER: begin
                    perf_enable = 1'b0;
                    throttle_active = 1'b0;
                    control_level = 2'b00;
                end

                MODE_NORMAL: begin
                    perf_enable = 1'b1;
                    throttle_active = 1'b0;
                    control_level = 2'b11;
                end

                MODE_THROTTLED: begin
                    perf_enable = 1'b1;
                    throttle_active = 1'b1;
                    control_level = 2'b01;
                end

                default: begin
                    perf_enable = 1'b0;
                    throttle_active = 1'b0;
                    control_level = 2'b00;
                end
            endcase

            if (throttle_request) begin
                throttle_active = 1'b1;
                control_level = 2'b01;
            end
        end
    end

endmodule


module workload_predictor (
    input wire clk,
    input wire rst,
    input wire class_valid,
    input wire [1:0] workload_class,
    output reg [1:0] workload_trend
);

    localparam TREND_STABLE = 2'b00;
    localparam TREND_RISING = 2'b01;
    localparam TREND_FALLING = 2'b10;
    localparam TREND_RESERVED = 2'b11;

    reg [1:0] previous_class;
    reg previous_valid;

    always @(posedge clk) begin
        if (rst) begin
            previous_class <= 2'b00;
            previous_valid <= 1'b0;
            workload_trend <= TREND_STABLE;
        end
        else if (class_valid) begin
            if (workload_class == 2'b11)
                workload_trend <= TREND_RESERVED;
            else if (!previous_valid)
                workload_trend <= TREND_STABLE;
            else if (workload_class > previous_class)
                workload_trend <= TREND_RISING;
            else if (workload_class < previous_class)
                workload_trend <= TREND_FALLING;
            else
                workload_trend <= TREND_STABLE;

            previous_class <= workload_class;
            previous_valid <= 1'b1;
        end
    end

endmodule

`default_nettype wire
