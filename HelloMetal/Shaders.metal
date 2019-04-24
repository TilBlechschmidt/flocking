/// Copyright (c) 2019 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

#include <metal_stdlib>
#import "./Loki/loki_header.metal"
using namespace metal;

struct Boid {
    packed_float3 position;
    packed_float3 velocity;
    packed_float3 acceleration;
};

struct Settings {
    float separationRange;
    float cohesionRange;
    float alignmentRange;

    float separationStrength;
    float cohesionStrength;
    float alignmentStrength;
};

__constant float maxSpeed = 0.01;
//__constant float maxForce = 0.0001;

//uint neighbors_of_boid(device Boid* boid_array, const device uint* boid_count, const uint boid_id, const float perception_range, device uint* neighbors) {
//    uint count = 0;
//
//    for (uint i = 0; i < *boid_count; i++) {
//        if (i == boid_id || distance(boid_array[boid_id].position, boid_array[i].position) > perception_range) continue;
//        neighbors[count] = i;
//    }
//
//    return count;
//}

bool is_neighbor(device Boid* boid_array, const uint boid_id, const uint other_id, const float perception_range) {
    return other_id != boid_id && distance(boid_array[boid_id].position, boid_array[other_id].position) <= perception_range;
}

uint boid_id(uint2 gid, uint2 grid_dimensions) {
    return gid.y * grid_dimensions.x + gid.x;
}

kernel void boid_separation(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], const device Settings* settings [[ buffer(2) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    uint neighbor_count = 0;
    float3 steering = float3(0, 0, 0);

    for (uint i = 0; i < *boid_count; i++) {
        if (is_neighbor(boid_array, id, i, settings->separationRange)) { // 0.05
            float dist = distance(boid_array[id].position, boid_array[i].position);
            float3 directionVector = boid_array[id].position - boid_array[i].position;

            steering += directionVector / pow(max(1.0, dist), 2);
            neighbor_count++;
        }
    }

    if (neighbor_count == 0) {
        return;
    }

    steering /= neighbor_count;
    steering *= settings->separationStrength; // 0.01
//    steering = normalize(steering) * maxSpeed;
//    steering -= boid_array[id].velocity;
//    steering = clamp(steering, -maxForce, maxForce);

    // TODO Add a multiplier (ideally passed in through some config)
    boid_array[id].acceleration += steering;
}

kernel void boid_alignment(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], const device Settings* settings [[ buffer(2) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    uint neighbor_count = 0;
    float3 steering = float3(0, 0, 0);

    for (uint i = 0; i < *boid_count; i++) {
        if (is_neighbor(boid_array, id, i, settings->alignmentRange)) { // 0.15
            steering += boid_array[i].velocity;
            neighbor_count++;
        }
    }

    steering /= neighbor_count;
    steering *= settings->alignmentStrength; // 0.001
//    steering = normalize(steering) * maxSpeed;
//    steering -= boid_array[id].velocity;
//    steering = clamp(steering, -maxForce, maxForce);

    // TODO Add a multiplier (ideally passed in through some config)
    boid_array[id].acceleration += steering;
}


kernel void boid_cohesion(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], const device Settings* settings [[ buffer(2) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    uint neighbor_count = 0;
    float3 steering = float3(0, 0, 0);

    for (uint i = 0; i < *boid_count; i++) {
        if (is_neighbor(boid_array, id, i, settings->cohesionRange)) { // 0.2
            float3 delta = boid_array[i].position - boid_array[id].position;
            float dist = distance(boid_array[i].position, boid_array[id].position);
            steering += delta / pow(dist, 1.5);
            neighbor_count++;
        }
    }

    if (neighbor_count == 0) {
        return;
    }

    steering /= neighbor_count;
    steering *= settings->cohesionStrength; // 0.001
//    steering -= boid_array[id].position;
//    steering = normalize(steering) * maxSpeed;
//    steering -= boid_array[id].velocity;
//    steering = clamp(steering, -maxForce, maxForce);

    // TODO Add a multiplier (ideally passed in through some config)
    boid_array[id].acceleration += steering;
}

kernel void boid_wraparound(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    if (boid_array[id].position.x > 1) {
        boid_array[id].position.x = -1;
    } else if (boid_array[id].position.x < -1) {
        boid_array[id].position.x = 1;
    }

    if (boid_array[id].position.y > 1) {
        boid_array[id].position.y = -1;
    } else if (boid_array[id].position.y < -1) {
        boid_array[id].position.y = 1;
    }
}

kernel void boid_movement(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    boid_array[id].position += boid_array[id].velocity;
    boid_array[id].velocity += boid_array[id].acceleration;

    boid_array[id].velocity = clamp(boid_array[id].velocity, -maxSpeed, maxSpeed);
    boid_array[id].acceleration = float3(0, 0, 0); // -normalize(boid_array[id].position) * 0.0001;

    boid_array[id].position.z = 0.0;
}

//kernel void boid_flocking(device Boid* boid_array [[ buffer(0) ]], const device uint* boid_count [[ buffer(1) ]], uint2 gid [[thread_position_in_grid]]) {
//    uint index = gid.x;
//
//    // TODO Prevent this from becoming a copy
//    Boid ownBoid = boid_array[index];
//
//    float perceptionThreshold = 0.51;
//    float separationDistance = 0.1;
//
//    float3 cohesionVector = float3(0, 0, 0);
//    float3 separationVector = float3(0, 0, 0);
//
//    for (uint i = 0; i < *boid_count; i++) {
//        if (i == index) continue;
//
//        Boid otherBoid = boid_array[i];
//
//        float3 directionVector = float3(otherBoid.position.x - ownBoid.position.x, otherBoid.position.y - ownBoid.position.y, otherBoid.position.z - ownBoid.position.z);
//        float dist = distance(ownBoid.position, otherBoid.position);
//
//        if (dist > perceptionThreshold) continue;
//
//        // Calculate the cohesion
//        float3 normalizedDirectionVector = normalize(directionVector);
//        cohesionVector += normalizedDirectionVector * 0.001;
//
//        // Calculate the separation
//        if (dist < separationDistance) {
//            separationVector += normalizedDirectionVector * 0.002;
//        }
//
//        // Calculate the alignment
//
//        continue;
//    }
//
//    boid_array[index].position += cohesionVector;
//    boid_array[index].position -= separationVector;
//}

kernel void boid_to_triangles(device packed_float3* vertex_array [[ buffer(0) ]], const device Boid* boid_array [[ buffer(1) ]], const device uint* boid_count [[ buffer(2) ]], uint2 gid [[thread_position_in_grid]], uint2 grid_dimensions [[threads_per_grid]]) {
    uint index = boid_id(gid, grid_dimensions);
    if (index >= *boid_count) return;

    Boid b = boid_array[index];
    float3 position = b.position;

    float size = 0.003;

    float3 top = float3(position.x, position.y + size, position.z);
    float3 bottomLeft = float3(position.x + size / 2, b.position.y - size, position.z);
    float3 bottomRight = float3(position.x - size / 2, b.position.y - size, position.z);

    uint output_index = index * 3;
    vertex_array[output_index] = top;
    vertex_array[output_index + 1] = bottomLeft;
    vertex_array[output_index + 2] = bottomRight;
}

vertex float4 boid_vertex(const device packed_float3* vertex_array [[ buffer(0) ]], unsigned int vid [[ vertex_id ]]) {
    return float4(vertex_array[vid], 1.0);
}

fragment half4 boid_fragment() {
    return half4(47 / 256, 53 / 256, 66 / 256, 1.0);
}