# 08/02/2024
# Use time evolving block decimation (TEBD) to simulate the time evolution of a 1D Heisenebrg model.


using ITensors, ITensorMPS
using HDF5

let 
    N = 100
    cutoff = 1E-10
    τ = 0.02
    ttotal = 10.0

    
    # Define the dimmerazation parameter 
    δ = 0.1
    J₁ = 1.0
    J₂ = 2.0

    # Make an array of "site" indices
    s = siteinds("S=1/2", N; conserve_qns=true)

    # Make gates (1, 2), (2, 3), ..., (N-1, N)
    gates = ITensor[]
    for index in 1 : N - 2
        s₁ = s[index]
        s₂ = s[index + 1]
        s₃ = s[index + 2]

        # Add two-site gate for nearest-neighbor interactions
        if index % 2 == 1
            hj = 1/2 * J₁ * (1 + δ) * op("S+", s₁) * op("S-", s₂) + 1/2 * J₁ * (1 + δ) * op("S-", s₁) * op("S+", s₂) + J₁ * (1 + δ) * op("Sz", s₁) * op("Sz", s₂)
            Gj = exp(-im * τ/2 * hj)
        else
            hj = 1/2 * J₁ * (1 - δ) * op("S+", s₁) * op("S-", s₂) + 1/2 * J₁ * (1 - δ) * op("S-", s₁) * op("S+", s₂) + J₁ * (1 - δ) * op("Sz", s₁) * op("Sz", s₂)
            Gj = exp(-im * τ/2 * hj)
        end
        push!(gates, Gj)


        # Add two-site gate for next-nearest-neighbor interactions
        hj_tmp = 1/2 * J₂ * op("S+", s₁) * op("S-", s₃) + 1/2 * J₂ * op("S-", s₁) * op("S+", s₃) + J₂ * op("Sz", s₁) * op("Sz", s₃) 
        Gj_tmp = exp(-im * τ/2 * hj_tmp)    
        push!(gates, Gj_tmp)
    end

    # Add the last gate for the last two sites
    s₁ = s[N - 1]
    s₂ = s[N]
    if (N - 1) % 2 == 1
        hj = 1/2 * J₁ * (1 + δ) * op("S+", s₁) * op("S-", s₂) + 1/2 * J₁ * (1 + δ) * op("S-", s₁) * op("S+", s₂) + J₁ * (1 + δ) * op("Sz", s₁) * op("Sz", s₂)
        Gj = exp(-im * τ/2 * hj)
    else
        hj = 1/2 * J₁ * (1 - δ) * op("S+", s₁) * op("S-", s₂) + 1/2 * J₁ * (1 - δ) * op("S-", s₁) * op("S+", s₂) + J₁ * (1 - δ) * op("Sz", s₁) * op("Sz", s₂)
        Gj = exp(-im * τ/2 * hj)
    end
    push!(gates, Gj)
    
    # Add reverse gates due to the the symmetric Trotter decomposition
    append!(gates, reverse(gates))

    
    # Run DMRG simulation to obtain the ground-state wave function
    os = OpSum()
    for index = 1 : N - 2
        # Construct the Hamiltonian for the Heisenberg model
        # Consider the nearest-neighbor dimmerized interactions
        if index % 2 == 1
            os += 1/2 * J₁ * (1 + δ), "S+", index, "S-", index + 1
            os += 1/2 * J₁ * (1 + δ), "S-", index, "S+", index + 1
            os += J₁ * (1 + δ), "Sz", index, "Sz", index + 1
        else
            os += 1/2 * J₁ * (1 - δ), "S+", index, "S-", index + 1
            os += 1/2 * J₁ * (1 - δ), "S-", index, "S+", index + 1
            os += J₁ * (1 - δ), "Sz", index, "Sz", index + 1
        end

        # Consider the next-nearest-neighbor interactions
        os += 1/2 * J₂, "S+", index, "S-", index + 2    
        os += 1/2 * J₂, "S-", index, "S+", index + 2
        os += J₂, "Sz", index, "Sz", index + 2  
    end

    # Construct the MPO for the last two sites
    if (N - 1) % 2 == 1
        os += 1/2 * J₁ * (1 + δ), "S+", N - 1, "S-", N  
        os += 1/2 * J₁ * (1 + δ), "S-", N - 1, "S+", N
        os += J₁ * (1 + δ), "Sz", N - 1, "Sz", N
    else
        os += 1/2 * J₁ * (1 - δ), "S+", N - 1, "S-", N  
        os += 1/2 * J₁ * (1 - δ), "S-", N - 1, "S+", N
        os += J₁ * (1 - δ), "Sz", N - 1, "Sz", N
    end

    Hamiltonian = MPO(os, s)
    ψ₀ = MPS(s, n -> isodd(n) ? "Up" : "Dn")
    

    # Define parameters that are used in the DMRG optimization process
    nsweeps = 20
    maxdim = [20, 50, 200, 1000]
    states = [isodd(n) ? "Up" : "Dn" for n in 1:N]
    # ψ = randomMPS(s, states; linkdims = 10)
    E, ψ = dmrg(Hamiltonian, ψ₀; nsweeps, maxdim, cutoff)
    
    Sz₀ = expect(ψ, "Sz"; sites = 50 : 51)
    Czz₀ = correlation_matrix(ψ, "Sz", "Sz"; sites = 50 : 51)
    @show Sz₀
    @show Czz₀
    
    # center = div(N, 2)
    # ψ_copy = deepcopy(ψ)
    
    
    # # Apply a local operator Sz to the center of the chain
    # local_op = op("Sz", s[center])
    # ψ = apply(local_op, ψ; cutoff)  
    # normalize!(ψ)

    # # local_op = op("Sz", s[center])
    # # @show typeof(local_op)
    # # newA = local_op * ψ[center]
    # # newA = noprime(newA)
    # # ψ[center] = newA

    # # os_local = OpSum()
    # # os_local += 1/2, "Sz", center
    # # local_op = MPO(os_local, s)
    # # ψ = apply(local_op, ψ; cutoff)
    # # normalize!(ψ)
   
    # Sz₁ = expect(ψ, "Sz"; sites = 50 : 51)
    # Czz₁ = correlation_matrix(ψ, "Sz", "Sz"; sites = 50 : 51)
    # @show Sz₁
    # @show Czz₁

    # Czz = Matrix{ComplexF64}(undef, Int(ttotal / τ), N * N)
    # Czz_unequaltime = Matrix{ComplexF64}(undef, Int(ttotal / τ), N)
    # @show size(Czz_unequaltime)
    # chi = Matrix{Float64}(undef, Int(ttotal / τ), N - 1)
    # @show size(chi)
    # Sz_all = Matrix{ComplexF64}(undef, Int(ttotal / τ), N)


    # # Time evovle the original and perturbed wave functions
    # for t in 0 : τ : ttotal
    #     index = round(Int, t / τ) + 1
    #     @show index
    #     Sz = expect(ψ, "Sz"; sites = center)
    #     println("t = $t, Sz = $Sz")

    #     t ≈ ttotal && break
    #     ψ = apply(gates, ψ; cutoff)
    #     normalize!(ψ)
    #     chi[index, :] = linkdims(ψ)
    #     @show linkdims(ψ)

    #     ψ_copy = apply(gates, ψ_copy; cutoff)
    #     normalize!(ψ_copy)

    #     Czz[index, :] = correlation_matrix(ψ, "Sz", "Sz"; sites = 1 : N)
    #     Sz_all[index, :] = expect(ψ, "Sz"; sites = 1 : N)

    #     for site_index in collect(1 : N)
    #         tmp_os = OpSum()
    #         tmp_os += "Sz", site_index
    #         tmp_MPO = MPO(tmp_os, s)
    #         Czz_unequaltime[index, site_index] = inner(ψ_copy', tmp_MPO, ψ)
    #     end
    # end
    # # @show Czz_unequaltime

    
    h5open("Data/Heisenberg_Model_TEBD_N$(N)_Time$(ttotal)_tau$(τ)_update.h5", "w") do file
        write(file, "Psi", ψ)
        write(file, "Sz T=0", Sz₀)
        write(file, "Czz T=0", Czz₀)
        # write(file, "Czz_unequaltime", Czz_unequaltime)
        # write(file, "Czz", Czz)
        # write(file, "Sz", Sz_all)
        # write(file, "Bond", chi)
    end

    return
end