bl_info = {
    "name": "Socket Stream",
    "blender": (2, 80, 0),
    "category": "Object",
}

import bpy
import socket
import json
import threading
import mathutils

server = None
clients = []

previous_camera_coordinates = None

# Function to send view information over the socket
def send_view():
    global previous_camera_coordinates

    view_matrix = None
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            rv3d = area.spaces[0].region_3d
            view_matrix = rv3d.view_matrix.copy()
            break

    # Extract rotation and translation information from the view matrix
    rotation = view_matrix.to_quaternion()
    translation = view_matrix.translation

    # Check if camera coordinates have changed
    if view_matrix != previous_camera_coordinates:
        # Convert rotation to euler angles
        euler_rotation = rotation.to_euler()
        # Create a dictionary with view information
        view_data = {
            "rotation": (-euler_rotation.x, -euler_rotation.y, -euler_rotation.z),
            "translation": (translation.x, translation.y, translation.z),
        }

        print("Sending view data...")
        print("Position: " + str(view_data["translation"]))
        # Convert the dictionary to a string and send it over the socket
        # data_str = str(view_data)
        # send as json
        data_str = json.dumps(view_data)
        for client in clients:
            try:
                print(f"Sending view data to {client}")
                client.sendall(data_str.encode("utf-8"))
                client.sendall(b"\n")
            except socket.error:
                pass

        # Update the previous camera coordinates
        previous_camera_coordinates = view_matrix

    return 0.01666


# A function to accept new connections
def accept_connection():
    try:
        # Attempt to accept a new connection
        client_socket, address = server.accept()
        print(f"Connection from {address} has been established!")
        clients.append(client_socket)

        # Set the new client socket to non-blocking
        client_socket.setblocking(0)
    except socket.error:
        pass
    return 0.1


def try_register():
    try:
        bpy.app.timers.register(send_view, first_interval=0.01666)
        bpy.app.timers.register(accept_connection, first_interval=0.1)
        print("Camera stream addon has been registered")
    except:
        print("Failed to register timers, retrying...")
        threading.Timer(1, try_register).start()


# Register and unregister functions
def register():
    print("Registering camera stream addon")
    # Create a server socket
    global server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Bind the socket to a specific address and port
    server.bind(("127.0.0.1", 12348))

    # Enable the socket to accept connections
    server.listen(5)

    server.setblocking(0)

    threading.Timer(1, try_register).start()


def unregister():
    bpy.app.timers.unregister(send_view)
    bpy.app.timers.unregister(accept_connection)
    server.close()


if __name__ == "__main__":
    register()
