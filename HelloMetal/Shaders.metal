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
    float maxVelocity;
    uint teamID;
};

struct InteractionNode {
    packed_float3 position;
    float repulsionStrength;
};

struct GlobalSettings {
    bool teamsEnabled;
    bool wrapEnabled;
};

struct TeamSettings {
    float separationRange;
    float cohesionRange;
    float alignmentRange;

    float separationStrength;
    float cohesionStrength;
    float alignmentStrength;
    float teamStrength;
    float maximumSpeedMultiplier;
};

uint boid_id(uint2 gid, uint2 grid_dimensions) {
    return gid.y * grid_dimensions.x + gid.x;
}

float3 rotate(float3 vector, float byAngle) {
    return float3(
                  vector.x * cos(byAngle) - vector.y * sin(byAngle),
                  vector.x * sin(byAngle) + vector.y * cos(byAngle),
                  vector.z
                  );
}

float angle(float3 ofVector) {
    return atan2(ofVector.y, ofVector.x);
}

float falloff(float dist, float maximumDistance) {
    float distancePercentage = dist / maximumDistance;
    return 1 - sqrt(distancePercentage);
}

kernel void boid_flocking(
        device Boid* boid_array [[ buffer(0) ]],
        const device uint* boid_count [[ buffer(1) ]],

        device InteractionNode* interaction_array [[ buffer(2) ]],
        const device uint* interaction_count [[ buffer(3) ]],

        constant GlobalSettings &global_settings [[ buffer(4) ]],
        constant TeamSettings* team_settings_array [[ buffer(5) ]],

        uint2 gid [[thread_position_in_grid]],
        uint2 grid_dimensions [[threads_per_grid]])
{
    uint id = boid_id(gid, grid_dimensions);
    if (id >= *boid_count) return;

    // TODO Change the friends every n-th iteration instead of every time

    TeamSettings team_settings = team_settings_array[boid_array[id].teamID];

    float width = 2.0;
    float height = 2.0;

    float scale = 0.91 / 1024.0; // / 512;
    float friendRadius = 60.0 * scale;
    float crowdRadius = friendRadius / 1.3;
    float avoidRadius = 90.0 * scale;
    float cohesionRadius = friendRadius * 5;
    float maxVelocity = boid_array[id].maxVelocity * scale; // 2.1 * scale;

    bool doWrap = global_settings.wrapEnabled;
    bool considerTeams = global_settings.teamsEnabled;

    // Step 1: Wrap around at the screen edges
    if (doWrap) {
        while (boid_array[id].position.x > width / 2) {
            boid_array[id].position.x -= width;
        }

        while (boid_array[id].position.x < -(width / 2)) {
            boid_array[id].position.x += width;
        }

        while (boid_array[id].position.y > height / 2) {
            boid_array[id].position.y -= height;
        }

        while (boid_array[id].position.y < -(height / 2)) {
            boid_array[id].position.y += height;
        }
    } else {
        if (boid_array[id].position.x > width / 2) {
            boid_array[id].position.x = width / 2;
            boid_array[id].velocity.x *= -1.0;
        } else if (boid_array[id].position.x < -(width / 2)) {
            boid_array[id].position.x = -(width / 2);
            boid_array[id].velocity.x *= -1.0;
        } else if (boid_array[id].position.y > height / 2) {
            boid_array[id].position.y = height / 2;
            boid_array[id].velocity.y *= -1.0;
        } else if (boid_array[id].position.y < -(height / 2)) {
            boid_array[id].position.y = -(height / 2);
            boid_array[id].velocity.y *= -1.0;
        }
    }

    // Step 2-5: Iterate over all neighbors
    float3 alignmentDirection = float3(0, 0, 0);
    float3 separationDirection = float3(0, 0, 0);
    float3 cohesionDirection = float3(0, 0, 0);
    float3 teamDirection = float3(0, 0, 0);

    uint alignmentCount = 0;
    uint separationCount = 0;
    uint cohesionCount = 0;
    uint teamCount = 0;

    for (uint i = 0; i < *boid_count; i++) {
        float d = distance(boid_array[id].position, boid_array[i].position);
        float3 directionVector = boid_array[id].position - boid_array[i].position;

        if ((!considerTeams || boid_array[id].teamID == boid_array[i].teamID) && d > 0) {
            // Step 2: Calculate alignment
            if (d < friendRadius && length(boid_array[i].velocity) > 0) {
                alignmentDirection += normalize(boid_array[i].velocity) * falloff(d, friendRadius);
                alignmentCount++;
            }

            // Step 3: Calculate separation
            if (d < crowdRadius && length(directionVector) > 0) {
                separationDirection += normalize(directionVector) * falloff(d, crowdRadius);
                separationCount++;
            }

            // Step 4: Calculate cohesion
            if (d < cohesionRadius) {
                cohesionDirection += boid_array[i].position;
                cohesionCount++;
            }
        } else if (d > 0) {
            // Step 3: Calculate team separation
            float radius = crowdRadius * 1.5;
            if (d < radius && length(boid_array[id].velocity) > 0) {
                teamDirection += normalize(directionVector) * falloff(d, avoidRadius);
                teamCount++;
            }
        }
    }

    // Step 5: Calculate repulsion/adhesion
    float3 repulsionDirection = float3(0, 0, 0);
    uint repulsionCount = 0;

    for (uint i = 0; i < *interaction_count; i++) {
        float d = abs(distance(boid_array[id].position, interaction_array[i].position));

        if (d > 0 && d < avoidRadius && length(boid_array[id].velocity) > 0) {
            float distanceMultiplier = falloff(d, avoidRadius) * 100;
            float intensity = length(boid_array[id].velocity);
            float3 direction = normalize(boid_array[id].position - interaction_array[i].position);

            repulsionDirection += direction * intensity * distanceMultiplier;
            repulsionCount++;
        }
    }

    // Step 6: Do post-processing on the values from Steps 2-5
    if (alignmentCount > 0) alignmentDirection /= alignmentCount;
    if (separationCount > 0) separationDirection /= separationCount;
    if (repulsionCount > 0) repulsionDirection /= repulsionCount;
    if (teamCount > 0) teamDirection /= teamCount;

    if (cohesionCount > 0) {
        cohesionDirection /= cohesionCount;
        cohesionDirection -= boid_array[id].position;
        cohesionDirection = normalize(cohesionDirection) * 0.05;
    }

    // Step 7: Calculate noise

    // Step 8: Scale calculated values
    alignmentDirection *= scale * team_settings.alignmentStrength;
    separationDirection *= scale * team_settings.separationStrength;
    cohesionDirection *= scale * team_settings.cohesionStrength;
    repulsionDirection *= scale * 35;
    teamDirection *= scale * team_settings.teamStrength;

    // Interlude: Wait for all threads before mutating ourselves
    threadgroup_barrier(mem_flags::mem_device);

    // Step 9: Add values to velocity
    boid_array[id].velocity += alignmentDirection;
    boid_array[id].velocity += separationDirection;
    boid_array[id].velocity += cohesionDirection;
    boid_array[id].velocity += repulsionDirection;
    boid_array[id].velocity += teamDirection;
    // TODO Add noise

    // Step 10: Limit velocity
    if (length(boid_array[id].velocity) > maxVelocity * 1.5 * team_settings.maximumSpeedMultiplier) {
        boid_array[id].velocity = normalize(boid_array[id].velocity) * maxVelocity;
    }

    // Step 11: Apply velocity to position
    boid_array[id].position += boid_array[id].velocity;
    boid_array[id].position.z = 0.0;
}

struct VertexIn {
    packed_float3 position;
    float speed;
    uint teamID;
};

kernel void boid_to_triangles(
      device VertexIn* vertex_array [[ buffer(0) ]],
      const device Boid* boid_array [[ buffer(1) ]],
      const device uint* boid_count [[ buffer(2) ]],
      uint2 gid [[thread_position_in_grid]],
      uint2 grid_dimensions [[threads_per_grid]])
{
    uint index = boid_id(gid, grid_dimensions);
    if (index >= *boid_count) return;

    Boid b = boid_array[index];
    float3 position = b.position;

    float size = 0.005;

    float3 top = float3(0, size, 0);
    float3 bottomLeft = float3(size / 2, -size, 0);
    float3 bottomRight = float3(-size / 2, -size, 0);

    float heading = angle(b.velocity) - M_PI_2_F;
    float speed = length(b.velocity);
    uint team = b.teamID;

    uint output_index = index * 3;
    vertex_array[output_index] = { position + rotate(top, heading), speed, team }; // float4(position + rotate(top, heading), speed);
    vertex_array[output_index + 1] = { position + rotate(bottomLeft, heading), speed, team }; // float4(position + rotate(bottomLeft, heading), speed);
    vertex_array[output_index + 2] = { position + rotate(bottomRight, heading), speed, team }; // float4(position + rotate(bottomRight, heading), speed);
}


// MARK: - Boid render shaders

struct VertexOut {
    float4 position [[position]];
    float speed;
    uint teamID;
};

vertex VertexOut boid_vertex(const device VertexIn* vertex_array [[ buffer(0) ]], unsigned int vid [[ vertex_id ]]) {
    VertexOut out;

    out.position = float4(vertex_array[vid].position, 1.0);
    out.speed = vertex_array[vid].speed;
    out.teamID = vertex_array[vid].teamID;

    return out;
}

fragment half4 boid_fragment(VertexOut in [[stage_in]]) {
    half4 base_color = half4(0, 0, 0, 0);

    if (in.teamID == 0) {
        base_color = half4(0.0, 0.51, 0.56, 0.0);
    } else if (in.teamID == 1) {
        base_color = half4(0.9, 0.3, 0.1, 0.0);
    }

    float normalizedSpeed = clamp(in.speed * 200, 0.0, 1.0);
    float colorMix = pow(normalizedSpeed, 0.7) * 0.5;
    half4 maximumColor = half4(1, 1, 1, 1);

    return half4(
        base_color.x + (maximumColor.x - base_color.x) * colorMix,
        base_color.y + (maximumColor.y - base_color.y) * colorMix,
        base_color.z + (maximumColor.z - base_color.z) * colorMix,
        base_color.w + (maximumColor.w - base_color.w) * colorMix
    );

//    float colorMultiplier = in.speed * 200;
//    return half4(0.0, colorMultiplier, colorMultiplier, 1.0);
}


// MARK: - Interaction render shaders

struct InteractionVertexOut {
    float4 position [[position]];
    float size [[point_size]];
};

vertex InteractionVertexOut interaction_vertex(const device InteractionNode* interaction_array [[ buffer(0) ]], unsigned int vid [[ vertex_id ]]) {
    InteractionVertexOut out;

    out.position = float4(interaction_array[vid].position.xyz, 1.0);
    out.size = interaction_array[vid].repulsionStrength + 50;

    return out;
}

fragment half4 interaction_fragment(InteractionVertexOut in [[stage_in]]) {
    return half4(1.0, 0, 0, 1.0);
}
