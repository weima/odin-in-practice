// Original companion; Linux truncation behavior is pinned to core/net/socket_linux.odin at a2fb372.
package main

import "core:fmt"
import "core:net"
import "core:time"

run :: proc() -> bool {
    server, bind_err := net.make_bound_udp_socket(net.IP4_Loopback, 0)
    if bind_err != nil { return false }
    defer net.close(server)
    client, client_err := net.make_bound_udp_socket(net.IP4_Loopback, 0)
    if client_err != nil { return false }
    defer net.close(client)
    endpoint, endpoint_err := net.bound_endpoint(server)
    if endpoint_err != nil { return false }
    if net.set_option(server, .Receive_Timeout, time.Second) != nil { return false }
    request := [4]u8{1, 2, 3, 4}
    sent, send_err := net.send_udp(client, request[:], endpoint)
    if send_err != nil || sent != len(request) { return false }
    received: [8]u8
    n, _, recv_err := net.recv_udp(server, received[:])
    if recv_err != nil || n != 4 { return false }
    for value, index in request { if received[index] != value { return false } }
    sent, send_err = net.send_udp(client, request[:], endpoint)
    if send_err != nil || sent != 4 { return false }
    short: [2]u8
    short_n, _, truncation_err := net.recv_udp(server, short[:])
    if short_n != 2 || truncation_err != .Excess_Truncated { return false }
    fmt.println("UDP loopback: datagram and Linux truncation checked")
    return true
}

main :: proc() { assert(run(), "UDP loopback failed") }
