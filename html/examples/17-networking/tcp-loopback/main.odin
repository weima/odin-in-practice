// Original companion; API/source baseline: core/net/socket.odin and socket_linux.odin at 84bc3fc.
package main

import "core:fmt"
import "core:net"
import "core:time"

receive_exact :: proc(socket: net.TCP_Socket, target: []u8) -> bool {
    total := 0
    for total < len(target) {
        // Intentionally tiny read window: no dependence on send/receive boundaries.
        n, err := net.recv_tcp(socket, target[total:][:1])
        if err != nil || n == 0 { return false }
        total += n
    }
    return true
}

run :: proc() -> bool {
    listener, listen_err := net.listen_tcp({net.IP4_Loopback, 0}, backlog=1)
    if listen_err != nil { fmt.eprintln("listen:", listen_err); return false }
    defer net.close(listener)
    endpoint, endpoint_err := net.bound_endpoint(listener)
    if endpoint_err != nil { return false }
    client, connect_err := net.dial_tcp(endpoint)
    if connect_err != nil { return false }
    defer net.close(client)
    server, _, accept_err := net.accept_tcp(listener)
    if accept_err != nil { return false }
    defer net.close(server)
    if net.set_option(client, .Receive_Timeout, time.Second) != nil { return false }
    if net.set_option(server, .Receive_Timeout, time.Second) != nil { return false }
    if net.set_option(client, .Send_Timeout, time.Second) != nil { return false }
    if net.set_option(server, .Send_Timeout, time.Second) != nil { return false }
    request := [4]u8{'p', 'i', 'n', 'g'}
    sent, send_err := net.send_tcp(client, request[:])
    if send_err != nil || sent != len(request) { return false }
    received: [4]u8
    if !receive_exact(server, received[:]) || received != request { return false }
    sent, send_err = net.send_tcp(server, received[:])
    if send_err != nil || sent != len(received) { return false }
    reply: [4]u8
    if !receive_exact(client, reply[:]) || reply != request { return false }
    if net.shutdown(client, .Send) != nil { return false }
    tail: [1]u8
    n, eof_err := net.recv_tcp(server, tail[:])
    if n != 0 || eof_err != nil { return false }
    fmt.println("TCP loopback: exact read, reply, and half-close checked")
    return true
}

main :: proc() { assert(run(), "TCP loopback failed") }
