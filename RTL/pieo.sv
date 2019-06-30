// synopsys translate_off
`timescale 1 ns / 1 ps
// synopsys translate_on

//`define SIMULATION

import pieo_datatypes::*;

/* NULL element is all 1s, i.e., e.id = '1, e.rank = '1, and e.send_time = '1
 * It is assumed that '1 for rank and send_time values equals Infinity
*/

module pieo
(
    input clk,
    input rst,

    /* signal that PIEO has reset all the internal datastructures */
    output logic pieo_reset_done_out,

    /* signal to start the PIEO scheduler
     * this signal should be set once PIEO has reset all it's datastructures
    */
    input start,

    /* signal that PIEO is ready for the next primitive operation
     * wait for this signal to be set before issuing the next primitive operation
    */
    output logic pieo_ready_for_nxt_op_out,

    /* interface for enqueue(f) operation */
    input enqueue_f_in,
    input SublistElement f_in,
    output logic enq_valid_out,
    output logic [$clog2(NUM_OF_SUBLIST):0] f_enqueued_in_sublist_out,

    /* input interface for dequeue() operation */
    input dequeue_in,
    input [TIME_LOG-1:0] curr_time_in,

    /* input interface for dequeue(f) operation */
    input dequeue_f_in,
    input [ID_LOG-1:0] flow_id_in,
    input [$clog2(NUM_OF_SUBLIST)-1:0] sublist_id_in,

    /* output interface for dequeue() and dequeue(f) operations */
    output logic deq_valid_out,
    output SublistElement deq_element_out,

    /* element moved during a primitive operation */
    output logic [ID_LOG:0] flow_id_moved_out,
    output logic [$clog2(NUM_OF_SUBLIST):0] flow_id_moved_to_sublist_out
);

`ifdef SIMULATION
    integer f;
`endif

    //latching the inputs
    SublistElement f_in_reg;
    logic dequeue_in_reg;
    logic [TIME_LOG-1:0] curr_time_in_reg;
    logic dequeue_f_in_reg;
    logic [ID_LOG-1:0] flow_id_in_reg;

    typedef enum {
        LEFT,
        RIGHT,
        FREE,
        NONE
    } neigh_types;

    //ordered list in SRAM
    logic enable_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic write_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [$clog2(NUM_OF_SUBLIST)-1:0] address_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    SublistElement wr_data_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    SublistElement rd_data_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    logic enable_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic write_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [$clog2(NUM_OF_SUBLIST)-1:0] address_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    SublistElement wr_data_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    SublistElement rd_data_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    generate
    genvar i;
    for (i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin : rank_sublist
        dual_port_bram # (
            .RAM_WIDTH($bits(SublistElement)),
            .RAM_ADDR_BITS($clog2(NUM_OF_SUBLIST))
        ) rank_sublist (
            .clk(clk),
            .Addr_A(address_A[i]),
            .Addr_B(address_B[i]),
            .Data_In_A(wr_data_A[i]),
            .Data_In_B(wr_data_B[i]),
            .En_A(enable_A[i]),
            .En_B(enable_B[i]),
            .Wen_A(write_A[i]),
            .Wen_B(write_B[i]),
            .Data_Out_A(rd_data_A[i]),
            .Data_Out_B(rd_data_B[i])
        );
    end
    endgenerate

    logic enable_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic write_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [$clog2(NUM_OF_SUBLIST)-1:0] address_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] wr_data_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] rd_data_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    logic enable_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic write_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [$clog2(NUM_OF_SUBLIST)-1:0] address_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] wr_data_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] rd_data_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    generate
    genvar j;
    for (j=0; j<NUM_OF_ELEMENTS_PER_SUBLIST; j=j+1) begin : pred_fifo
        dual_port_bram # (
            .RAM_WIDTH(TIME_LOG),
            .RAM_ADDR_BITS($clog2(NUM_OF_SUBLIST))
        ) pred_sublist (
            .clk(clk),
            .Addr_A(address_AA[j]),
            .Addr_B(address_BB[j]),
            .Data_In_A(wr_data_AA[j]),
            .Data_In_B(wr_data_BB[j]),
            .En_A(enable_AA[j]),
            .En_B(enable_BB[j]),
            .Wen_A(write_AA[j]),
            .Wen_B(write_BB[j]),
            .Data_Out_A(rd_data_AA[j]),
            .Data_Out_B(rd_data_BB[j])
        );
    end
    endgenerate

    SublistElement rd_data_A_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    SublistElement rd_data_B_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] rd_data_AA_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    logic [TIME_LOG-1:0] rd_data_BB_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    always @(posedge clk) begin
        if (~rst) begin
            rd_data_A_reg <= rd_data_A;
            rd_data_B_reg <= rd_data_B;
            rd_data_AA_reg <= rd_data_AA;
            rd_data_BB_reg <= rd_data_BB;
        end
    end

    //pointer array in flip-flops
    PointerElement pointer_array [NUM_OF_SUBLIST-1:0];
    logic [$clog2(NUM_OF_SUBLIST)-1:0] free_list_head_reg;

    //pointer array multiplexer
    logic [$clog2(NUM_OF_SUBLIST)-1:0] s_idx_reg;
    PointerElement s;
    PointerElement s_neigh_enq;
    neigh_types s_neigh_enq_type;
    PointerElement s_neigh_deq;
    neigh_types s_neigh_deq_type;
    PointerElement s_free;
    logic [$clog2(NUM_OF_ELEMENTS_PER_SUBLIST)-1:0] element_moving_idx;
    PointerElement s_reg;
    PointerElement s_neigh_reg;
    neigh_types s_neigh_type_reg;
    PointerElement s_free_reg;

    assign s = pointer_array[s_idx_reg];
    assign s_neigh_enq = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array[s_idx_reg+1].full)
                        ? s_free : pointer_array[s_idx_reg+1];
    assign s_neigh_enq_type = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array[s_idx_reg+1].full)
                        ? FREE : RIGHT;
    assign s_neigh_deq = (pointer_array[s_idx_reg].full
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array[s_idx_reg+1].full
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array[s_idx_reg+1]
                        : (pointer_array[s_idx_reg].full
                            & s_idx_reg > 0
                            & ~pointer_array[s_idx_reg-1].full)
                        ? pointer_array[s_idx_reg-1] : 0;
    assign s_neigh_deq_type = (pointer_array[s_idx_reg].full
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array[s_idx_reg+1].full
                            & s_idx_reg+1 != free_list_head_reg)
                        ? RIGHT
                        : (pointer_array[s_idx_reg].full
                            & s_idx_reg > 0
                            & ~pointer_array[s_idx_reg-1].full)
                        ? LEFT : NONE;
    assign s_free = pointer_array[free_list_head_reg];
    assign element_moving_idx = (pointer_array[s_idx_reg].full
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array[s_idx_reg+1].full
                            & s_idx_reg+1 != free_list_head_reg)
                        ? 0
                        : (pointer_array[s_idx_reg].full
                            & s_idx_reg > 0
                            & ~pointer_array[s_idx_reg-1].full)
                        ? pointer_array[s_idx_reg-1].num-1 : '1;

    //priority encoder for pointer array
    logic [NUM_OF_SUBLIST-1:0] bit_vector;
    logic [$clog2(NUM_OF_SUBLIST)-1:0] encode;
    logic [$clog2(NUM_OF_SUBLIST)-1:0] encode_reg;
    logic valid;
    logic valid_reg;

    priority_encode_log#(
        .width(NUM_OF_SUBLIST),
        .log_width($clog2(NUM_OF_SUBLIST))
    ) pri_encoder(bit_vector, encode, valid);

    //priority encoder for rank sublist
    logic [NUM_OF_SUBLIST/2-1:0] bit_vector_A;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_A;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_A_reg;
    logic valid_A;
    logic valid_A_reg;

    priority_encode_log#(
        .width(NUM_OF_SUBLIST/2),
        .log_width($clog2(NUM_OF_SUBLIST/2))
    ) pri_encoder_A(bit_vector_A, encode_A, valid_A);

    //priority encoder for pred sublist
    logic [NUM_OF_SUBLIST/2-1:0] bit_vector_AA;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_AA;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_AA_reg;
    logic valid_AA;
    logic valid_AA_reg;

    priority_encode_log#(
        .width(NUM_OF_SUBLIST/2),
        .log_width($clog2(NUM_OF_SUBLIST/2))
    ) pri_encoder_AA(bit_vector_AA, encode_AA, valid_AA);

    //priority encoder for pred sublist
    logic [NUM_OF_SUBLIST/2-1:0] bit_vector_BB;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_BB;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_BB_reg;
    logic valid_BB;
    logic valid_BB_reg;

    priority_encode_log#(
        .width(NUM_OF_SUBLIST/2),
        .log_width($clog2(NUM_OF_SUBLIST/2))
    ) pri_encoder_BB(bit_vector_BB, encode_BB, valid_BB);

    typedef enum {
`ifdef SIMULATION
        PRINT,
        CONT_PRINTING,
`endif
        RESET,
        RESET_DONE,
        IDLE,
        ENQ_FETCH_SUBLIST_FROM_MEM,
        POS_TO_ENQUEUE,
        ENQ_WRITE_BACK_TO_MEM,
        DEQ_FETCH_SUBLIST_FROM_MEM,
        POS_TO_DEQUEUE,
        DEQ_WRITE_BACK_TO_MEM
    } pieo_ops;

    pieo_ops curr_state, nxt_state;

    reg [31:0] curr_address;

    SublistElement element_moving_reg;
    logic [$clog2(NUM_OF_ELEMENTS_PER_SUBLIST)-1:0] element_moving_idx_reg;
    logic [TIME_LOG-1:0] pred_moving_reg;

    logic [1:0] enqueue_case_reg;

    logic [$clog2(NUM_OF_SUBLIST)-1:0] idx_enq_reg;
    logic [$clog2(NUM_OF_SUBLIST)-1:0] idx_enq;

    SublistElement element_dequeued_reg;
    always @(posedge clk) begin
        if (~rst) element_dequeued_reg <= rd_data_A[encode_A];
    end

    SublistElement element_moving;
    assign element_moving = rd_data_B[element_moving_idx_reg];

    logic [TIME_LOG-1:0] pred_val_deq;

`ifdef SIMULATION
    reg [63:0] cntr;
    reg [63:0] insertion_cnt;
    reg [63:0] deletion_cnt;
`endif

    always_comb begin
        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
            enable_A[i] = 0;
            write_A[i] = 0;
            address_A[i] = '0;
            wr_data_A[i] = '0;
            enable_B[i] = 0;
            write_B[i] = 0;
            address_B[i] = '0;
            wr_data_B[i] = '0;
            enable_AA[i] = 0;
            write_AA[i] = 0;
            address_AA[i] = '0;
            wr_data_AA[i] = '0;
            enable_BB[i] = 0;
            write_BB[i] = 0;
            address_BB[i] = '0;
            wr_data_BB[i] = '0;
        end
        nxt_state = curr_state;
        pieo_reset_done_out = 0;
        pieo_ready_for_nxt_op_out = 0;
        enq_valid_out = 0;
        f_enqueued_in_sublist_out = '1;
        deq_valid_out = 0;
        deq_element_out = '1;
        flow_id_moved_out = '1;
        flow_id_moved_to_sublist_out = '1;
        bit_vector = '0;
        bit_vector_A = '0;
        bit_vector_AA = '0;
        bit_vector_BB = '0;
        idx_enq = 0; //temp vals
        pred_val_deq = '0; //temp vals

        case(curr_state)
            RESET: begin
                for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                    enable_A[i] = 1;
                    write_A[i] = 1;
                    address_A[i] = curr_address;
                    wr_data_A[i].id = 0;
                    wr_data_A[i].rank = '1;
                    wr_data_A[i].send_time = '1;
                    enable_AA[i] = 1;
                    write_AA[i] = 1;
                    address_AA[i] = curr_address;
                    wr_data_AA[i] = '1;
                    if (curr_address == NUM_OF_SUBLIST - 1) begin
                        nxt_state = RESET_DONE;
                    end
                end
            end

            RESET_DONE: begin
                pieo_reset_done_out = 1;
                nxt_state = IDLE;
            end

            IDLE: begin
                if (start) begin
                    pieo_ready_for_nxt_op_out = 1;
                    if (enqueue_f_in) begin
                        //figure out the right sublist to enq
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            bit_vector[i]
                                = (pointer_array[i].smallest_rank > f_in.rank);
                        end
                        nxt_state = ENQ_FETCH_SUBLIST_FROM_MEM;
                    end
                    else if (dequeue_in) begin
                        //figure out the right sublist to deq
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            bit_vector[i]
                                = (curr_time_in
                                    >= pointer_array[i].smallest_send_time);
                        end
                        nxt_state = DEQ_FETCH_SUBLIST_FROM_MEM;
                    end else if (dequeue_f_in) begin
                        //figure out the right sublist to deq
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            bit_vector[i]
                                = (sublist_id_in == pointer_array[i].id);
                        end
                        nxt_state = DEQ_FETCH_SUBLIST_FROM_MEM;
                    end
                end
            end

            ENQ_FETCH_SUBLIST_FROM_MEM: begin
                if (valid_reg) begin
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        enable_A[i] = 1;
                        write_A[i] = 0;
                        address_A[i] = s.id;
                        enable_AA[i] = 1;
                        write_AA[i] = 0;
                        address_AA[i] = s.id;

                        if (s.full && s_neigh_enq_type != NONE) begin
                            enable_B[i] = 1;
                            write_B[i] = 0;
                            address_B[i] = s_neigh_enq.id;
                            enable_BB[i] = 1;
                            write_BB[i] = 0;
                            address_BB[i] = s_neigh_enq.id;
                        end
                    end
                    nxt_state = POS_TO_ENQUEUE;
                end
            end

            POS_TO_ENQUEUE: begin
                if (~s_reg.full) begin
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        bit_vector_A[i] = (rd_data_A[i].rank > f_in_reg.rank);
                    end
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        bit_vector_AA[i] = (rd_data_AA[i] > f_in_reg.send_time);
                    end
                end else begin
                    //new element is getting inserted in B
                    if (f_in_reg.rank
                    >= rd_data_A[NUM_OF_ELEMENTS_PER_SUBLIST-1].rank) begin
                        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                            bit_vector_BB[i] = (rd_data_BB[i] > f_in_reg.send_time);
                        end
                    end
                    else begin //new element in A, last element of A in B
                        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                            bit_vector_A[i] = (rd_data_A[i].rank > f_in_reg.rank);
                        end
                        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                            bit_vector_AA[i] = (rd_data_AA[i] > f_in_reg.send_time);
                        end
                        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                            bit_vector_BB[i] = (rd_data_BB[i]
                              > rd_data_A[NUM_OF_ELEMENTS_PER_SUBLIST-1].send_time);
                        end
                    end
                end
                nxt_state = ENQ_WRITE_BACK_TO_MEM;
            end

            ENQ_WRITE_BACK_TO_MEM: begin
                case (enqueue_case_reg)
                    0: begin
                        if (valid_A_reg & valid_AA_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_reg.id;
                            flow_id_moved_out = '1;
                            flow_id_moved_to_sublist_out = '1;
                            for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)
                            begin
                                enable_A[i] = 1;
                                write_A[i] = 1;
                                address_A[i] = s_reg.id;
                                if (i < encode_A_reg) begin
                                    wr_data_A[i] = rd_data_A_reg[i];
                                end else if (i == encode_A_reg) begin
                                    wr_data_A[i] = f_in_reg;
                                end else if (i != 0) begin
                                    wr_data_A[i] = rd_data_A_reg[i-1];
                                end
                                enable_AA[i] = 1;
                                write_AA[i] = 1;
                                address_AA[i] = s_reg.id;
                                if (i < encode_AA_reg) begin
                                    wr_data_AA[i] = rd_data_AA_reg[i];
                                end else if (i == encode_AA_reg) begin
                                    wr_data_AA[i] = f_in_reg.send_time;
                                end else if (i != 0) begin
                                    wr_data_AA[i] = rd_data_AA_reg[i-1];
                                end
                            end
`ifdef SIMULATION
                            nxt_state = PRINT;
`else
                            nxt_state = IDLE;
`endif
                        end
                    end

                    1: begin
                        if (valid_BB_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_neigh_reg.id;
                            flow_id_moved_out = '1;
                            flow_id_moved_to_sublist_out = '1;
                            for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)
                            begin
                                enable_B[i] = 1;
                                write_B[i] = 1;
                                address_B[i] = s_neigh_reg.id;
                                if (i == 0) begin
                                    wr_data_B[i] = f_in_reg;
                                end else if (i != 0) begin
                                    wr_data_B[i] = rd_data_B_reg[i-1];
                                end
                                enable_BB[i] = 1;
                                write_BB[i] = 1;
                                address_BB[i] = s_neigh_reg.id;
                                if (i < encode_BB_reg) begin
                                    wr_data_BB[i] = rd_data_BB_reg[i];
                                end else if (i == encode_BB_reg) begin
                                    wr_data_BB[i] = f_in_reg.send_time;
                                end else if (i != 0) begin
                                    wr_data_BB[i] = rd_data_BB_reg[i-1];
                                end
                            end
`ifdef SIMULATION
                            nxt_state = PRINT;
`else
                            nxt_state = IDLE;
`endif
                        end
                    end

                    2: begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_reg.id;
                            flow_id_moved_out = element_moving_reg.id;
                            flow_id_moved_to_sublist_out = s_neigh_reg.id;
                            idx_enq = (valid_AA_reg) ? encode_AA_reg : idx_enq_reg;
                            for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)
                            begin
                                enable_A[i] = 1;
                                write_A[i] = 1;
                                address_A[i] = s_reg.id;
                                if (i < encode_A_reg) begin
                                    wr_data_A[i] = rd_data_A_reg[i];
                                end else if (i == encode_A_reg) begin
                                    wr_data_A[i] = f_in_reg;
                                end else if (i !=0) begin
                                    wr_data_A[i] = rd_data_A_reg[i-1];
                                end
                                enable_AA[i] = 1;
                                write_AA[i] = 1;
                                address_AA[i] = s_reg.id;
                                if (pred_moving_reg == f_in_reg.send_time) begin
                                    wr_data_AA[i] = rd_data_AA_reg[i];
                                end else if (pred_moving_reg < f_in_reg.send_time) begin
                                    if (rd_data_AA_reg[i] < pred_moving_reg) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end else if (rd_data_AA_reg[i] == pred_moving_reg
                                                || i < idx_enq) begin
                                        if (i == idx_enq-1)
                                            wr_data_AA[i] = f_in_reg.send_time;
                                        else if (i < NUM_OF_ELEMENTS_PER_SUBLIST-1)
                                            wr_data_AA[i] = rd_data_AA_reg[i+1];
                                    end else  begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end
                                end else begin
                                    if (i < idx_enq) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end else if (i == idx_enq) begin
                                        wr_data_AA[i] = f_in_reg.send_time;
                                    end else if (i > idx_enq && i != 0
                                                && rd_data_AA_reg[i] <= pred_moving_reg) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i-1];
                                    end else begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end
                                end
                                enable_B[i] = 1;
                                write_B[i] = 1;
                                address_B[i] = s_neigh_reg.id;
                                if (i == 0) begin
                                    wr_data_B[i] = element_moving_reg;
                                end else if (i != 0) begin
                                    wr_data_B[i] = rd_data_B_reg[i-1];
                                end
                                enable_BB[i] = 1;
                                write_BB[i] = 1;
                                address_BB[i] = s_neigh_reg.id;
                                if (i < encode_BB_reg) begin
                                    wr_data_BB[i] = rd_data_BB_reg[i];
                                end else if (i == encode_BB_reg) begin
                                    wr_data_BB[i] = pred_moving_reg;
                                end else if (i != 0) begin
                                    wr_data_BB[i] = rd_data_BB_reg[i-1];
                                end
                            end
`ifdef SIMULATION
                            nxt_state = PRINT;
`else
                            nxt_state = IDLE;
`endif
                        end
                    end

                    default: begin
                        enq_valid_out = 0;
                        f_enqueued_in_sublist_out = '1;
                        flow_id_moved_out = '1;
                        flow_id_moved_to_sublist_out = '1;
                        for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)
                        begin
                            enable_A[i] = 1;
                            write_A[i] = 1;
                            address_A[i] = s_reg.id;
                            wr_data_A[i] = rd_data_A_reg[i];
                            enable_AA[i] = 1;
                            write_AA[i] = 1;
                            address_AA[i] = s_reg.id;
                            wr_data_AA[i] = rd_data_AA_reg[i];
                            enable_B[i] = 1;
                            write_B[i] = 1;
                            address_B[i] = s_neigh_reg.id;
                            wr_data_B[i] = rd_data_B_reg[i];
                            enable_BB[i] = 1;
                            write_BB[i] = 1;
                            address_BB[i] = s_neigh_reg.id;
                            wr_data_BB[i] = rd_data_BB_reg[i];
                        end
`ifdef SIMULATION
                        nxt_state = PRINT;
`else
                        nxt_state = IDLE;
`endif
                    end
                endcase
            end

            DEQ_FETCH_SUBLIST_FROM_MEM: begin
                if (~valid_reg) begin
                    deq_valid_out = 1;
                    deq_element_out.id = '1;
                    deq_element_out.rank = '1;
                    deq_element_out.send_time = '1;
                    flow_id_moved_out = '1;
                    flow_id_moved_to_sublist_out = '1;
`ifdef SIMULATION
                    nxt_state = PRINT;
`else
                    nxt_state = IDLE;
`endif
                end else if (valid_reg) begin
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        enable_A[i] = 1;
                        write_A[i] = 0;
                        address_A[i] = s.id;
                        enable_AA[i] = 1;
                        write_AA[i] = 0;
                        address_AA[i] = s.id;

                        if (s.full && s_neigh_deq_type != NONE) begin
                            enable_B[i] = 1;
                            write_B[i] = 0;
                            address_B[i] = s_neigh_deq.id;
                            enable_BB[i] = 1;
                            write_BB[i] = 0;
                            address_BB[i] = s_neigh_deq.id;
                        end
                    end
                    nxt_state = POS_TO_DEQUEUE;
                end
            end

            POS_TO_DEQUEUE: begin
                if (dequeue_in_reg) begin
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        bit_vector_A[i] = (curr_time_in_reg >= rd_data_A[i].send_time);
                    end
                end else if (dequeue_f_in_reg) begin
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        bit_vector_A[i] = (flow_id_in_reg == rd_data_A[i].id);
                    end
                end

                if (s_neigh_type_reg != NONE) begin
                    //insertion
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                        bit_vector_AA[i] =
                            (rd_data_AA[i] > element_moving.send_time);
                    end
                    //deletion
                    for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                        bit_vector_BB[i] =
                            (rd_data_BB[i] == element_moving.send_time);
                    end
                end
                nxt_state = DEQ_WRITE_BACK_TO_MEM;
            end

            DEQ_WRITE_BACK_TO_MEM: begin
                if (~valid_A_reg) begin
                    deq_valid_out = 1;
                    deq_element_out.id = '1;
                    deq_element_out.rank = '1;
                    deq_element_out.send_time = '1;
                    flow_id_moved_out = '1;
                    flow_id_moved_to_sublist_out = '1;
`ifdef SIMULATION
                    nxt_state = PRINT;
`else
                    nxt_state = IDLE;
`endif
                end else begin
                    if (s_neigh_type_reg == NONE) begin
                        if (valid_A_reg) begin
                            deq_valid_out = 1;
                            deq_element_out = element_dequeued_reg;
                            flow_id_moved_out = '1;
                            flow_id_moved_to_sublist_out = '1;
                            for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                                enable_A[i] = 1;
                                write_A[i] = 1;
                                address_A[i] = s_reg.id;
                                if (i < encode_A_reg) begin
                                    wr_data_A[i] = rd_data_A_reg[i];
                                end else begin
                                    if (i == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_A[i].id = 0;
                                        wr_data_A[i].rank = '1;
                                        wr_data_A[i].send_time = '1;
                                    end else begin
                                        wr_data_A[i] = rd_data_A_reg[i+1];
                                    end
                                end
                                enable_AA[i] = 1;
                                write_AA[i] = 1;
                                address_AA[i] = s_reg.id;
                                if (rd_data_AA_reg[i] < element_dequeued_reg.send_time) begin
                                    wr_data_AA[i] = rd_data_AA_reg[i];
                                end else begin
                                    if (i == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_AA[i] = '1;
                                    end else begin
                                        wr_data_AA[i] = rd_data_AA_reg[i+1];
                                    end
                                end
                            end
`ifdef SIMULATION
                            nxt_state = PRINT;
`else
                            nxt_state = IDLE;
`endif
                        end
                    end else begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                            deq_valid_out = 1;
                            deq_element_out = element_dequeued_reg;
                            flow_id_moved_out = element_moving_reg.id;
                            flow_id_moved_to_sublist_out = s_reg.id;

                            pred_val_deq = element_dequeued_reg.send_time;
                            idx_enq = (valid_AA_reg) ? encode_AA_reg : idx_enq_reg;
                            for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1)begin
                                enable_A[i] = 1;
                                write_A[i] = 1;
                                address_A[i] = s_reg.id;
                                if (s_neigh_type_reg == LEFT) begin
                                    if (i == 0) begin
                                        wr_data_A[i] = element_moving_reg;
                                    end else if (i <= encode_A_reg) begin
                                        wr_data_A[i] = rd_data_A_reg[i-1];
                                    end else begin
                                        wr_data_A[i] = rd_data_A_reg[i];
                                    end
                                end else begin
                                    if (i < encode_A_reg) begin
                                        wr_data_A[i] = rd_data_A_reg[i];
                                    end else begin
                                        if (i == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                            wr_data_A[i] = element_moving_reg;
                                        end else begin
                                            wr_data_A[i] = rd_data_A_reg[i+1];
                                        end
                                    end
                                end
                                enable_AA[i] = 1;
                                write_AA[i] = 1;
                                address_AA[i] = s_reg.id;
                                if (pred_val_deq == pred_moving_reg) begin
                                    wr_data_AA[i] = rd_data_AA_reg[i];
                                end else if (pred_val_deq < pred_moving_reg) begin
                                    if (rd_data_AA_reg[i] < pred_val_deq) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end else if (rd_data_AA_reg[i] == pred_val_deq
                                                || i < idx_enq) begin
                                        if (i == idx_enq-1)
                                            wr_data_AA[i] = pred_moving_reg;
                                        else if (i < NUM_OF_ELEMENTS_PER_SUBLIST-1)
                                            wr_data_AA[i] = rd_data_AA_reg[i+1];
                                    end else  begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end
                                end else begin
                                    if (i < idx_enq) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end else if (i == idx_enq) begin
                                        wr_data_AA[i] = pred_moving_reg;
                                    end else if (i > idx_enq && i != 0
                                                && rd_data_AA_reg[i] <= pred_val_deq) begin
                                        wr_data_AA[i] = rd_data_AA_reg[i-1];
                                    end else begin
                                        wr_data_AA[i] = rd_data_AA_reg[i];
                                    end
                                end
                                enable_B[i] = 1;
                                write_B[i] = 1;
                                address_B[i] = s_neigh_reg.id;
                                if (s_neigh_type_reg == LEFT) begin
                                    if (i == s_neigh_reg.num-1) begin
                                        wr_data_B[i].id = 0;
                                        wr_data_B[i].rank = '1;
                                        wr_data_B[i].send_time = '1;
                                    end else begin
                                        wr_data_B[i] = rd_data_B_reg[i];
                                    end
                                end else begin
                                    if (i < NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_B[i] = rd_data_B_reg[i+1];
                                    end else begin
                                        wr_data_B[i] = rd_data_B_reg[i];
                                    end
                                end
                                enable_BB[i] = 1;
                                write_BB[i] = 1;
                                address_BB[i] = s_neigh_reg.id;
                                if (i < encode_BB_reg) begin
                                    wr_data_BB[i] = rd_data_BB_reg[i];
                                end else begin
                                    if (i == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_BB[i] = '1;
                                    end else begin
                                        wr_data_BB[i] = rd_data_BB_reg[i+1];
                                    end
                                end
                            end
`ifdef SIMULATION
                            nxt_state = PRINT;
`else
                            nxt_state = IDLE;
`endif
                        end
                    end
                end
            end
`ifdef SIMULATION
            PRINT: begin
                for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                    enable_A[i] = 1;
                    write_A[i] = 0;
                    address_A[i] = pointer_array[cntr].id;
                    enable_AA[i] = 1;
                    write_AA[i] = 0;
                    address_AA[i] = pointer_array[cntr].id;
                    nxt_state = CONT_PRINTING;
                end
            end

            CONT_PRINTING: begin
                for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                    if (cntr < NUM_OF_SUBLIST) begin
                        enable_A[i] = 1;
                        write_A[i] = 0;
                        address_A[i] = pointer_array[cntr].id;
                        enable_AA[i] = 1;
                        write_AA[i] = 0;
                        address_AA[i] = pointer_array[cntr].id;
                    end
                    if (cntr == NUM_OF_SUBLIST) begin
                        nxt_state = IDLE;
                    end
                end
            end
`endif
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            curr_state <= RESET;
            free_list_head_reg <= 0;
            //initialize pointer array
            for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                pointer_array[i].id = i;
                pointer_array[i].smallest_rank = '1;
                pointer_array[i].smallest_send_time = '1;
                pointer_array[i].full = 0;
                pointer_array[i].num = 0;
            end
            curr_address <= 0;
            enqueue_case_reg <= 3;
            idx_enq_reg <= 0;
            f_in_reg <= 0;
            dequeue_in_reg <= 0;
            curr_time_in_reg <= 0;
            dequeue_f_in_reg <= 0;
            flow_id_in_reg <= 0;
`ifdef SIMULATION
            insertion_cnt <= 0;
            deletion_cnt <= 0;
`endif
        end else begin
            curr_state <= nxt_state;

            if (curr_state == RESET) begin
                curr_address <= curr_address + 1;
`ifdef SIMULATION
                $display("Resetting sublist = %0d", curr_address);
`endif
            end else if (curr_state == IDLE) begin
                if (start) begin
                    f_in_reg <= f_in;
                    dequeue_in_reg <= dequeue_in;
                    curr_time_in_reg <= curr_time_in;
                    dequeue_f_in_reg <= dequeue_f_in;
                    flow_id_in_reg <= flow_id_in;
                    valid_reg <= valid;
                    encode_reg <= encode;
                    if (enqueue_f_in) begin
                        s_idx_reg <= (encode==0) ? encode : encode-1;
                    end else if (dequeue_in || dequeue_f_in) begin
                        s_idx_reg <= encode;
                    end
`ifdef SIMULATION
                    curr_address <= 0;
                    cntr <= 0;
                    if (enqueue_f_in) begin
                        $fwrite(f,"\nENQUEUE -- %0d -- %0d %0d %0d\n", insertion_cnt,
                            f_in.id, f_in.rank, f_in.send_time);
                        insertion_cnt <= insertion_cnt + 1;
                    end else if (dequeue_in) begin
                        $fwrite(f, "\nDEQUEUE -- %0d -- %0d\n",
                            deletion_cnt, curr_time_in);
                        deletion_cnt <= deletion_cnt + 1;
                    end else if (dequeue_f_in) begin
                        $fwrite(f, "\nDEQUEUE_F -- %0d -- %0d -- %0d\n",
                            deletion_cnt, flow_id_in, sublist_id_in);
                        deletion_cnt <= deletion_cnt + 1;
                    end
`endif
                end
            end else if (curr_state == ENQ_FETCH_SUBLIST_FROM_MEM) begin
                if (valid_reg) begin
                    s_reg <= s;
                    s_neigh_reg <= s_neigh_enq;
                    s_neigh_type_reg <= s_neigh_enq_type;
                    s_free_reg <= s_free;
                end
            end else if (curr_state == POS_TO_ENQUEUE) begin
                element_moving_reg <= rd_data_A[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                pred_moving_reg <= rd_data_A[NUM_OF_ELEMENTS_PER_SUBLIST-1].send_time;
                if (~s_reg.full) begin
                    valid_A_reg <= valid_A;
                    encode_A_reg <= encode_A;
                    valid_AA_reg <= valid_AA;
                    encode_AA_reg <= encode_AA;
                    enqueue_case_reg <= 0;
                    //update pointer array
                    if (s_idx_reg == free_list_head_reg) begin
                        free_list_head_reg <= free_list_head_reg + 1;
                    end
                end else begin
                    //new element is getting inserted in B
                    if (f_in_reg.rank
                    >= rd_data_A[NUM_OF_ELEMENTS_PER_SUBLIST-1].rank) begin
                        valid_BB_reg <= valid_BB;
                        encode_BB_reg <= encode_BB;
                        enqueue_case_reg <= 1;
                    end else begin
                        //new element in A, last element of A in B
                        valid_A_reg <= valid_A;
                        encode_A_reg <= encode_A;
                        valid_AA_reg <= valid_AA;
                        encode_AA_reg <= encode_AA;
                        valid_BB_reg <= valid_BB;
                        encode_BB_reg <= encode_BB;
                        enqueue_case_reg <= 2;
                        if (f_in_reg.send_time >= rd_data_AA[NUM_OF_ELEMENTS_PER_SUBLIST-1])
                            idx_enq_reg <= NUM_OF_ELEMENTS_PER_SUBLIST;
                        else
                            idx_enq_reg <= 0;
                    end
                    //update pointer array
                    if (s_neigh_type_reg == FREE) begin
                        for (integer i = 0; i < NUM_OF_SUBLIST-1; i=i+1) begin
                            if (i > s_idx_reg &&
                                i < free_list_head_reg) begin
                                pointer_array[i+1] <= pointer_array[i];
                                if (i == s_idx_reg+1) begin
                                    pointer_array[i] <= s_free_reg;
                                end
                            end
                        end
                        free_list_head_reg <= free_list_head_reg + 1;
                    end else if (s_idx_reg+1 == free_list_head_reg) begin
                        free_list_head_reg <= free_list_head_reg + 1;
                    end
                end
            end else if (curr_state == ENQ_WRITE_BACK_TO_MEM) begin
                if (enqueue_case_reg == 0) begin
                    if (valid_A_reg & valid_AA_reg) begin
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            if (i == s_idx_reg) begin
                                pointer_array[i].id <= s_reg.id;
                                pointer_array[i].smallest_rank <=
                                    (encode_A_reg == 0) ? f_in_reg.rank : rd_data_A_reg[0].rank;
                                pointer_array[i].smallest_send_time <=
                                    (encode_AA_reg == 0) ? f_in_reg.send_time : rd_data_AA_reg[0];
                                pointer_array[i].full
                                    <= (s_reg.full || s_reg.num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array[i].num <= s_reg.num + 1;
                            end
                        end
                    end
                end else if (enqueue_case_reg == 1) begin
                    if (valid_BB_reg) begin
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            if (i == s_idx_reg+1) begin
                                pointer_array[i].id <= s_neigh_reg.id;
                                pointer_array[i].smallest_rank <= f_in_reg.rank;
                                pointer_array[i].smallest_send_time <=
                                    (encode_BB_reg == 0) ? f_in_reg.send_time : rd_data_BB_reg[0];
                                pointer_array[i].full
                                    <= (s_neigh_reg.num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array[i].num <= s_neigh_reg.num + 1;
                            end
                        end
                    end
                end else if (enqueue_case_reg == 2) begin
                    if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                        for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                            if (i == s_idx_reg) begin
                                pointer_array[i].id <= s_reg.id;
                                pointer_array[i].smallest_rank <=
                                    (encode_A_reg == 0) ? f_in_reg.rank : rd_data_A_reg[0].rank;
                                if (rd_data_A_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1].send_time
                                    == rd_data_AA_reg[0]) begin
                                    pointer_array[i].smallest_send_time
                                        <= (f_in_reg.send_time < rd_data_AA_reg[1])
                                            ? f_in_reg.send_time : rd_data_AA_reg[1];
                                end else begin
                                    pointer_array[i].smallest_send_time
                                        <= (f_in_reg.send_time < rd_data_AA_reg[0])
                                            ? f_in_reg.send_time : rd_data_AA_reg[0];
                                end
                                pointer_array[i].full
                                    <= (s_reg.full || s_reg.num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array[i].num <= s.num;
                            end else if (i == s_idx_reg+1) begin
                                pointer_array[i].id <= s_neigh_reg.id;
                                pointer_array[i].smallest_rank <=
                                    rd_data_A_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1].rank;
                                pointer_array[i].smallest_send_time <=
                                    (encode_BB_reg == 0)
                                    ? rd_data_A_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1]
                                        .send_time
                                    : rd_data_BB_reg[0];
                                pointer_array[i].full
                                    <= (s_neigh_reg.num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array[i].num <= s_neigh_reg.num + 1;
                            end
                        end
                    end
                end
            end else if (curr_state == DEQ_FETCH_SUBLIST_FROM_MEM) begin
                if (~valid_reg) begin
`ifdef SIMULATION
                    $fwrite(f,"DEQ ELEMENT -- %0d %0d %0d\n",
                        0, (2**RANK_LOG)-1, (2**TIME_LOG)-1);
`endif
                end
                else if (valid_reg) begin
                    s_reg <= s;
                    s_neigh_reg <= s_neigh_deq;
                    s_neigh_type_reg <= s_neigh_deq_type;
                    s_free_reg <= s_free;
                    element_moving_idx_reg <= element_moving_idx;
                end
            end else if (curr_state == POS_TO_DEQUEUE) begin
                valid_A_reg <= valid_A;
                encode_A_reg <= encode_A;
                valid_AA_reg <= valid_AA;
                encode_AA_reg <= encode_AA;
                valid_BB_reg <= valid_BB;
                encode_BB_reg <= encode_BB;
                if (s_reg.num == 1) begin
                    //re-arrange pointer array
                    for (integer i=0; i<NUM_OF_SUBLIST; i=i+1)
                    begin
                        if (i == free_list_head_reg-1) begin
                            pointer_array[i].id <= s_reg.id;
                            pointer_array[i].smallest_rank <= '1;
                            pointer_array[i].smallest_send_time <= '1;
                            pointer_array[i].full <= 0;
                            pointer_array[i].num <= 0;
                        end else if (i >= s_idx_reg
                                && i < free_list_head_reg
                                && i < NUM_OF_SUBLIST-1)begin
                            pointer_array[i] <= pointer_array[i+1];
                        end
                    end
                    free_list_head_reg <= free_list_head_reg - 1;
                end else begin
                    if (s_neigh_type_reg != NONE) begin
                        element_moving_reg <= element_moving;
                        pred_moving_reg <= element_moving.send_time;
                        if (rd_data_B[element_moving_idx_reg].send_time
                            >= rd_data_AA[NUM_OF_ELEMENTS_PER_SUBLIST-1]) begin
                                idx_enq_reg <= NUM_OF_ELEMENTS_PER_SUBLIST;
                        end else begin
                                idx_enq_reg <= 0;
                        end
                        if (s_neigh_reg.num == 1) begin
                            //re-arrange pointer array
                            for (integer i=0; i<NUM_OF_SUBLIST; i=i+1)
                            begin
                                if (i == free_list_head_reg-1) begin
                                    pointer_array[i].id <= s_neigh_reg.id;
                                    pointer_array[i].smallest_rank <= '1;
                                    pointer_array[i].smallest_send_time <= '1;
                                    pointer_array[i].full <= 0;
                                    pointer_array[i].num <= 0;
                                end else if (i >= ((s_neigh_type_reg==LEFT)
                                                    ? s_idx_reg-1 : s_idx_reg+1)
                                        && i < free_list_head_reg-1
                                        && i < NUM_OF_SUBLIST-1) begin
                                    pointer_array[i] <= pointer_array[i+1];
                                end
                            end
                            free_list_head_reg <= free_list_head_reg - 1;
                            if (s_neigh_type_reg == LEFT) s_idx_reg <= s_idx_reg-1;
                        end
                    end
                end
            end else if (curr_state == DEQ_WRITE_BACK_TO_MEM) begin
                if (~valid_A_reg) begin
`ifdef SIMULATION
                    $fwrite(f,"DEQ ELEMENT -- %0d %0d %0d\n",
                        0, (2**RANK_LOG)-1, (2**TIME_LOG)-1);
`endif
                end else begin
                    if (s_neigh_type_reg == NONE) begin
                        if (valid_A_reg) begin
    `ifdef SIMULATION
                            $fwrite(f,"DEQ ELEMENT -- %0d %0d %0d\n",
                                element_dequeued_reg.id,
                                element_dequeued_reg.rank,
                                element_dequeued_reg.send_time);
    `endif
                            if (s_reg.num != 1) begin
                                for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                                    if (i == s_idx_reg) begin
                                        pointer_array[i].id <= s_reg.id;
                                        pointer_array[i].smallest_rank <=
                                            (encode_A_reg == 0) ? rd_data_A_reg[1].rank
                                                            : rd_data_A_reg[0].rank;
                                        pointer_array[i].smallest_send_time
                                            <= (rd_data_AA_reg[0] == element_dequeued_reg.send_time)
                                                ? rd_data_AA_reg[1] : rd_data_AA_reg[0];
                                        pointer_array[i].full <= 0;
                                        pointer_array[i].num <= pointer_array[i].num - 1;
                                    end
                                end
                            end
                        end
                    end else begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
    `ifdef SIMULATION
                            $fwrite(f,"DEQ ELEMENT -- %0d %0d %0d\n",
                                element_dequeued_reg.id,
                                element_dequeued_reg.rank,
                                element_dequeued_reg.send_time);
    `endif
                            for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                                if (i == s_idx_reg) begin
                                    pointer_array[i].id <= s_reg.id;
                                    pointer_array[i].smallest_rank <= (s_neigh_type_reg==LEFT)
                                        ? element_moving_reg.rank
                                        : ((encode_A_reg == 0) ? rd_data_A_reg[1].rank
                                                               : rd_data_A_reg[0].rank);
                                    if (element_dequeued_reg.send_time == rd_data_AA_reg[0]) begin
                                        pointer_array[i].smallest_send_time
                                            <= (element_moving_reg.send_time < rd_data_AA_reg[1])
                                                ? element_moving_reg.send_time : rd_data_AA_reg[1];
                                    end else begin
                                        pointer_array[i].smallest_send_time
                                            <= (element_moving_reg.send_time < rd_data_AA_reg[0])
                                                ? element_moving_reg.send_time : rd_data_AA_reg[0];
                                    end
                                    pointer_array[i].full = s_reg.full;
                                    pointer_array[i].num = s_reg.num;
                                end
                            end
                            if (s_neigh_reg.num != 1) begin
                                if (s_neigh_type_reg == LEFT) begin
                                    for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                                        if (i == s_idx_reg-1) begin
                                            pointer_array[i].id <= s_neigh_reg.id;
                                            pointer_array[i].smallest_rank <= s_neigh_reg.smallest_rank;
                                            pointer_array[i].smallest_send_time
                                                <= (element_moving_reg.send_time == rd_data_BB_reg[0])
                                                ? rd_data_BB_reg[1] : rd_data_BB_reg[0];
                                            pointer_array[i].full <= s_neigh_reg.full;
                                            pointer_array[i].num <= s_neigh_reg.num - 1;
                                        end
                                    end
                                end else begin
                                    for (integer i=0; i<NUM_OF_SUBLIST; i=i+1) begin
                                        if (i == s_idx_reg+1) begin
                                            pointer_array[i].id <= s_neigh_reg.id;
                                            pointer_array[i].smallest_rank <=
                                                rd_data_B_reg[1].rank;
                                            pointer_array[i].smallest_send_time
                                                <= (rd_data_B_reg[0].send_time == rd_data_BB_reg[0])
                                                ? rd_data_BB_reg[1] : rd_data_BB_reg[0];
                                            pointer_array[i].full <= s_neigh_reg.full;
                                            pointer_array[i].num <= s_neigh_reg.num - 1;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
`ifdef SIMULATION
            end else if (curr_state == PRINT) begin
                cntr <= cntr + 1;
                $fwrite(f, "%0d SUBLIST - %0d %0d %0d %0d %0d", insertion_cnt,
                    pointer_array[cntr].id, pointer_array[cntr].smallest_rank,
                    pointer_array[cntr].smallest_send_time,
                    pointer_array[cntr].full,
                    pointer_array[cntr].num);
                $fwrite(f, "\n");
            end else if (curr_state == CONT_PRINTING) begin
                cntr <= cntr + 1;
                for (integer i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin
                    $fwrite(f, "%0d,%0d,%0d %0d -- ",
                        rd_data_A[i].id, rd_data_A[i].rank, rd_data_A[i].send_time,
                        rd_data_AA[i]);
                end
                $fwrite(f,"\n");
                $fwrite(f, "%0d SUBLIST - %0d %0d %0d %0d %0d", insertion_cnt,
                    pointer_array[cntr].id, pointer_array[cntr].smallest_rank,
                    pointer_array[cntr].smallest_send_time,
                    pointer_array[cntr].full,
                    pointer_array[cntr].num);
                $fwrite(f,"\n");
`endif
            end
        end
    end

`ifdef SIMULATION
    initial begin
        f = $fopen("out", "w");
    end
`endif
endmodule

/*
* This module is adopted from https://github.com/programmable-scheduling/pifo-hardware/blob/master/src/rtl/design/pifo.v
*/
module priority_encode_log #
(
    parameter width = NUM_OF_SUBLIST,
    parameter log_width = $clog2(NUM_OF_SUBLIST)
)
(
  decode,
  encode_reg,valid_reg
);
    localparam pot_width = 1 << log_width;

    input  [width-1:0]     decode;
    output [log_width-1:0] encode_reg;
    output                 valid_reg;

    wire [pot_width-1:0] pot_decode = {pot_width{1'b0}} | decode;

    reg [pot_width-1:0] part_idx [0:log_width-1];

    always_comb begin
      part_idx[0] = 0;
      for(integer i=0; i<pot_width; i=i+2) begin
        part_idx[0][i] = pot_decode[i] || pot_decode[i+1];
        part_idx[0][i+1] = !pot_decode[i];
      end
    end

    genvar lvar;
    generate for(lvar=1; lvar<log_width; lvar=lvar+1) begin : something
      always_comb begin
        part_idx[lvar] = 0;
        for(integer i=0; i<pot_width; i=i+(1<<(lvar+1))) begin
          part_idx[lvar][i] = part_idx[lvar-1][i] ||  part_idx[lvar-1][i+(1<<lvar)];
          part_idx[lvar][i+1 +: lvar] = part_idx[lvar-1][i] ? part_idx[lvar-1][i+1 +:lvar] : part_idx[lvar-1][i+(1<<lvar)+1 +:lvar];
          part_idx[lvar][i+1 + lvar] = !part_idx[lvar-1][i];
        end
      end
    end
    endgenerate

    assign valid_reg  = part_idx[log_width-1][0];
    assign encode_reg = part_idx[log_width-1][1+:log_width];
endmodule
