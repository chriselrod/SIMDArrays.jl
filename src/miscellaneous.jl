@generated function Base.zero(::Type{<:SizedSIMDArray{S,T}}) where {S,T}
    SV = S.parameters
    N = length(SV)
    Stup = ntuple(n -> SV[n], N)#unstable
    R, L = calculate_L_from_size(SV)
    quote
        out = SizedSIMDArray{$S,$T,$N,$R,$L}(undef)
        @inbounds @simd for i ∈ 1:$L
            out[i] = zero($T)
        end
        out
    end
end

@generated function Base.fill(::Type{<:SizedSIMDArray{S,T}}, v::T) where {S,T}
    SV = S.parameters
    N = length(SV)
    R, L = calculate_L_from_size(SV)
    quote
        out = SizedSIMDArray{$S,$T,$N,$R,$L}(undef)
        @inbounds @simd for i ∈ 1:$L #Here, we accept the risk that the buffer becomes subnormal?
            out[i] = v
        end
        out
    end
end
function Base.fill!(A::SizedSIMDArray{S,T,N,R,L}, x) where {S<:Tuple,T,N,R,L}
    xt = convert(T,x)
    @inbounds @simd for i ∈ 1:L
        A[i] = xt
    end
    A
end

@generated function Base.similar(::SizedSIMDArray{S,T}, v::Vararg{Int,N}) where {S,T,N}
    :(SizedSIMDArray(undef, Val(v), $T))
end
Base.similar(::SizedSIMDArray{S,T}) where {S,T} = SizedSIMDArray{S,T}(undef)
Base.similar(::SizedSIMDArray{S},::Type{T}) where {S,T} = SizedSIMDArray{S,T}(undef)
@generated function Base.copyto!(out::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size,L)
    V = Vec{VL,T}
    num_reps = L ÷ VL
    LT = L * T_size
    VLT = VL * T_size
    quote
        $(Expr(:meta, :inline))
        ptr_out, ptr_A = pointer(out), pointer(A)
        @inbounds for i ∈ 0:$VLT:$(LT-VLT)
            vstore!(ptr_out + i, vload($V, ptr_A + i))
        end
        out
    end
end
@generated function Base.copyto!(out::SizedSIMDVector{S,T,L}, A::SizedSIMDVector{S,T,L}) where {S,T,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size,L)
    V = Vec{VL,T}
    num_reps = L ÷ VL
    LT = L * T_size
    VLT = VL * T_size
    quote
        $(Expr(:meta, :inline))
        ptr_out, ptr_A = pointer(out), pointer(A)
        @inbounds for i ∈ 0:$VLT:$(LT-VLT)
            vstore!(ptr_out + i, vload($V, ptr_A + i))
        end
        out
    end
end
function Base.copyto!(out::SizedSIMDVector, A::AbstractArray)
    @boundscheck length(out) == length(A) || throw(BoundsError())
    T = eltype(out)
    @inbounds for i ∈ 1:length(out)
        out[i] = T(A[i])
    end
    out
end
@generated function Base.copyto!(out::SizedSIMDArray{S,T,N}, A::AbstractArray{T,N}) where {S,T,N}
    s = (S.parameters...,)
    quote
        #$(Expr(:meta, :propagate_inbounds))
        #@boundscheck $s == size(A) || throw(BoundsError())
        @inbounds Base.Cartesian.@nloops $N n d -> 1:($s)[d] begin
            (Base.Cartesian.@nref $N out n) = (Base.Cartesian.@nref $N A n)
        end
        out
    end
end

const SymmetricMatrix{P,T} = Symmetric{T, <: SizedSIMDMatrix{P,P,T}}
function Base.setindex!(S::SymmetricMatrix{P,T}, v, i::Integer, j::Integer) where {P,T}
    @boundscheck begin
        i, j = minmax(i, j)
        (j > P || i < 1) && throw(BoundsError())
    end
    S.data[i,j] = v
end

Base.copy(A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L} = copyto!(SizedSIMDArray{S,T,N,R,L}(undef), A)

@generated function scale!(out::SizedSIMDArray{S,T,N,R,L}, val::T) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    V = Vec{VL,T}
    num_reps = L ÷ VL
    LT = L * T_size
    VLT = VL * T_size
    quote
        ptr_out = pointer(out)
        v = vbroadcast($V ,val)
        for i ∈ 0:$VLT:$(LT-VLT)
            vstore!(ptr_out + i, evmul(vload($V, ptr_out + i), v))
        end
        out
    end
end

function LinearAlgebra.dot(A::SizedSIMDArray{S,T,N,R,L}, B::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    out = zero(T)
    @inbounds @simd for i ∈ 1:L
        out += A[i] * B[i]
    end
    out
end
function squared_norm(A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    out = zero(T)
    @inbounds @simd for i ∈ 1:L
        out += A[i] * A[i]
    end
    out
end
function LinearAlgebra.norm(A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    out = zero(T)
    @inbounds @simd for i ∈ 1:L
        out += A[i] * A[i]
    end
    @fastmath sqrt(out)
end
function LinearAlgebra.normalize!(A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    @fastmath n = 1/sqrt(squared_norm(A))
    @inbounds @simd for i ∈ 1:L
        A[i] *= n
    end
    A
end

function Base.maximum(A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    out = -Inf
    @inbounds @simd for i ∈ 1:L
        out = max(A[i], out)
    end
    out
end
function Base.maximum(f, A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    out = -Inf
    @inbounds @simd for i ∈ 1:L
        out = max(A[i], out)
    end
    out
end
@generated function Base.maximum(f::Union{Function, Type}, A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    V = Vec{VL,T}
    num_reps = L ÷ VL
    ureps, freps = divrem(num_reps, 4)
    LTf = freps * T_size
    LTf = freps * T_size
    VLT = VL * T_size
    if freps == 0
        if ureps == 0
            q = :(typemin(T))
        else
            q = quote
                ptr_A = pointer(A)
                Base.Cartesian.@nexprs 4 d -> fA_d = f( vload($V, ptr_A + (d-1)*$VLT ) )
                for i ∈ $(4VLT):$(4VLT):$(4T_size * (L-VL) )
                    Base.Cartesian.@nexprs 4 d -> fA_d = max(fA_d, f( vload($V, ptr_A + i + (d-1)*$VLT ) ))
                end
                maximum( max(max(fA_1,fA_2),max(fA_3,fA_4)) )
            end
        end
    elseif ureps == 0
        if freps == 1
            q = :(maximum(f(vload($V, pointer(A)))))
        else
            q = quote
                ptr_A = pointer(A)
                fA_0 = f( vload($V, ptr_A  ) )
                Base.Cartesian.@nexprs $(freps-1) d -> fA_d = max(fA_{d-1}, f( vload($V, ptr_A + d*$VLT ) ))
                maximum( $(Symbol(:fA_, freps-1)) )
            end
        end


    else # neither 0
        q = quote
            ptr_A = pointer(A)
            Base.Cartesian.@nexprs 4 d -> fA_d = f( vload($V, ptr_A + (d-1)*$VLT ) )
            for i ∈ $(4VLT):$(4VLT):$(4 * (ureps-1) * VLT )
                Base.Cartesian.@nexprs 4 d -> fA_d = max(fA_d, f( vload($V, ptr_A + i + (d-1)*$VLT ) ))
            end
            Base.Cartesian.@nexprs $freps d -> fA_d = max(fA_d, f( vload($V, ptr_A + d*$VLT + $(4ureps * VLT ) ) ))
            maximum( max(max(fA_1,fA_2),max(fA_3,fA_4)) )
        end

    end
    q
end
function maximum_abs(A::SizedSIMDArray)
    out = typemin(eltype(A))
    @inbounds for i ∈ 1:full_length(A)
        temp = abs(A[i])
        if temp > out
            out = temp
        end
    end
    out
end

# @generated function maxdiff(A::SizedSIMDArray{S,T,N,R,L}, B::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
#     T_size = sizeof(T)
#     VL = min(REGISTER_SIZE ÷ T_size, L)
#     V = Vec{VL,T}
#     num_reps = L ÷ VL
#     ureps, freps = divrem(num_reps, 4)
#     LTf = freps * T_size
#     LTf = freps * T_size
#     VLT = VL * T_size
#     if freps == 0
#         if ureps == 0
#             q = :(typemax(T))
#         else
#             q = quote
#                 ptr_A, ptr_B = pointer(A), pointer(B)
#                 Base.Cartesian.@nexprs 4 d -> fA_d = abs( vload($V, ptr_A + (d-1)*$VLT ) - vload($V, ptr_B + (d-1)*$VLT ) )
#                 for i ∈ $(4VLT):$(4VLT):$(T_size * (L-4VL) )
#                     Base.Cartesian.@nexprs 4 d -> fA_d = max(fA_d, abs( vload($V, ptr_A + i + (d-1)*$VLT ) - vload($V, ptr_B + i + (d-1)*$VLT ) ))
#                 end
#                 maximum( max(max(fA_1,fA_2),max(fA_3,fA_4)) )
#             end
#         end
#     elseif ureps == 0
#         if freps == 1
#             q = :(maximum(abs(vload($V, pointer(A))-vload($V, pointer(B)))))
#         else
#             q = quote
#                 ptr_A, ptr_B = pointer(A), pointer(B)
#                 fA_0 = abs( vload($V, ptr_A  ) - vload($V, ptr_B ) )
#                 Base.Cartesian.@nexprs $(freps-1) d -> fA_d = max(fA_{d-1}, abs( vload($V, ptr_A + d*$VLT ) - vload($V, ptr_B + d*$VLT ) ))
#                 maximum( $(Symbol(:fA_, freps-1)) )
#             end
#         end
#
#
#     else # neither 0
#         q = quote
#             ptr_A, ptr_B = pointer(A), pointer(B)
#             Base.Cartesian.@nexprs 4 d -> fA_d = abs( vload($V, ptr_A + (d-1)*$VLT ) - vload($V, ptr_B + (d-1)*$VLT ) )
#             for i ∈ $(4VLT):$(4VLT):$(4 * (ureps-1) * VLT )
#                 Base.Cartesian.@nexprs 4 d -> fA_d = max(fA_d, abs( vload($V, ptr_A + i + (d-1)*$VLT ) - vload($V, ptr_B + i + (d-1)*$VLT ) ) )
#             end
#             Base.Cartesian.@nexprs $freps d -> fA_d = max(fA_d, abs( vload($V, ptr_A + d*$VLT + $(4ureps*VLT ) ) - vload($V, ptr_B + d*$VLT + $(4ureps*VLT ) ) ))
#             maximum( max(max(fA_1,fA_2),max(fA_3,fA_4)) )
#         end
#
#     end
#     q
# end

@generated function reflect!(C::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        vB = vbroadcast($V, $(T(-1)))
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, evmul(vload($V, ptr_C), vB))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_C + $offset), vB))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, vload($V, ptr_C + i) * vB)
                    vstore!(ptr_C + i + $VLT, evmul(vload($V, ptr_C + i + $VLT), vB))
                    vstore!(ptr_C + i + $(2VLT), evmul(vload($V, ptr_C + i + $(2VLT)), vB))
                    vstore!(ptr_C + i + $(3VLT), evmul(vload($V, ptr_C + i + $(3VLT)), vB), )
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_C + $offset), vB))) )
        end

    end
    push!(q.args, :(nothing))
    q
end
@generated function reflect!(C::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        ptr_A = pointer(A)
        vB = vbroadcast($V, $(T(-1)))
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, evmul(vload($V, ptr_A), vB))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_A + $offset), vB))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, evmul(vload($V, ptr_A + i), vB))
                    vstore!(ptr_C + i + $VLT, evmul(vload($V, ptr_A + i + $VLT), vB))
                    vstore!(ptr_C + i + $(2VLT), evmul(vload($V, ptr_A + i + $(2VLT)), vB))
                    vstore!(ptr_C + i + $(3VLT), evmul(vload($V, ptr_A + i + $(3VLT)), vB))
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_A + $offset), vB))) )
        end

    end
    push!(q.args, :(nothing))
    q
end
@generated function scale!(C::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}, B::T) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        ptr_A = pointer(A)
        vB = vbroadcast($V, B)
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, evmul(vload($V, ptr_A), vB))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_A + $offset), vB))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, evmul(vload($V, ptr_A + i), vB))
                    vstore!(ptr_C + i + $VLT, evmul(vload($V, ptr_A + i + $VLT), vB))
                    vstore!(ptr_C + i + $(2VLT), evmul(vload($V, ptr_A + i + $(2VLT)), vB))
                    vstore!(ptr_C + i + $(3VLT), evmul(vload($V, ptr_A + i + $(3VLT)), vB))
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, evmul(vload($V, ptr_A + $offset), vB))) )
        end

    end
    push!(q.args, :(nothing))
    q
end
@generated function vsub!(C::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}, B::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,L,R}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        ptr_A = pointer(A)
        ptr_B = pointer(B)
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, vsub(vload($V, ptr_A), vload($V, ptr_B)))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, vsub(vload($V, ptr_A + $offset), vload($V, ptr_B + $offset)))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, vsub(vload($V, ptr_A + i), vload($V, ptr_B + i)))
                    vstore!(ptr_C + i + $VLT, vsub(vload($V, ptr_A + i + $VLT), vload($V, ptr_B + i + $VLT)))
                    vstore!(ptr_C + i + $(2VLT), vsub(vload($V, ptr_A + i + $(2VLT)), vload($V, ptr_B + i + $(2VLT))))
                    vstore!(ptr_C + i + $(3VLT), vsub(vload($V, ptr_A + i + $(3VLT)), vload($V, ptr_B + i + $(3VLT))))
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, vsub(vload($V, ptr_A + $offset), vload($V, ptr_B + $offset)))) )
        end

    end
    push!(q.args, :(nothing))
    q
end
@generated function vadd!(C::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}, B::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        ptr_A = pointer(A)
        ptr_B = pointer(B)
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, vadd(vload($V, ptr_A), vload($V, ptr_B)))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, vadd(vload($V, ptr_A + $offset), vload($V, ptr_B + $offset)))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, vadd(vload($V, ptr_A + i), vload($V, ptr_B + i)))
                    vstore!(ptr_C + i + $VLT, vadd(vload($V, ptr_A + i + $VLT), vload($V, ptr_B + i + $VLT)))
                    vstore!(ptr_C + i + $(2VLT), vadd(vload($V, ptr_A + i + $(2VLT)), vload($V, ptr_B + i + $(2VLT))))
                    vstore!(ptr_C + i + $(3VLT), vadd(vload($V, ptr_A + i + $(3VLT)), vload($V, ptr_B + i + $(3VLT))))
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, vadd(vload($V, ptr_A + $offset), vload($V, ptr_B + $offset)))) )
        end

    end
    push!(q.args, :(nothing))
    q
end
@generated function vadd!(C::SizedSIMDArray{S,T,N,R,L}, A::SizedSIMDArray{S,T,N,R,L}, α::T, B::SizedSIMDArray{S,T,N,R,L}) where {S,T,N,R,L}
    T_size = sizeof(T)
    VL = min(REGISTER_SIZE ÷ T_size, L)
    VLT = VL * T_size
    V = Vec{VL,T}

    iter = L ÷ VL
    q = quote
        ptr_C = pointer(C)
        ptr_A = pointer(A)
        ptr_B = pointer(B)
        vα = vbroadcast($V, α)
    end

    if iter <= 8
        push!(q.args, :(vstore!(ptr_C, vmuladd(vload($V, ptr_B),vα,vload($V, ptr_A)))) )
        for i ∈ 1:iter-1
            offset = i*VLT
            push!(q.args, :(vstore!(ptr_C + $offset, vmuladd(vload($V, ptr_B + $offset), vα, vload($V, ptr_A + $offset)))) )
        end
    else
        rep, rem = divrem(iter, 4)
        if (rep == 1 && rem == 0) || (rep >= 1 && rem != 0)
            rep -= 1
            rem += 4
        end
        push!(q.args,
            quote
                for i ∈ 0:$(4VLT):$(4VLT*(rep-1))
                    vstore!(ptr_C + i, vmuladd(vload($V, ptr_B + i),vα,vload($V, ptr_A + i)))
                    vstore!(ptr_C + i + $VLT, vmuladd(vload($V, ptr_B + i + $VLT),vα,vload($V, ptr_A + i + $VLT)))
                    vstore!(ptr_C + i + $(2VLT), vmuladd(vload($V, ptr_B + i + $(2VLT)),vα,vload($V, ptr_A + i + $(2VLT))))
                    vstore!(ptr_C + i + $(3VLT), vmuladd(vload($V, ptr_B + i + $(3VLT)),vα,vload($V, ptr_A + i + $(3VLT))))
                end
            end
        )
        for i ∈ 1:rem
            offset = VLT*(i + 4rep)
            push!(q.args, :(vstore!(ptr_C + $offset, vmuladd(vload($V, ptr_B + $offset), vα, vload($V, ptr_A + $offset)))) )
        end

    end
    push!(q.args, :(nothing))
    q
end


@inline Base.pointer(x::Symmetric{T,SizedSIMDMatrix{P,P,T,R,L}}) where {P,T,R,L} = pointer(x.data)

function BFGS_update_quote(Mₖ,Pₖ,stride_AD,T)
    T_size = sizeof(T)
    AD_stride = stride_AD * T_size
    W = REGISTER_SIZE ÷ T_size
    Q, r = divrem(stride_AD, W) #Assuming stride_AD is a multiple of W
    if Q > 0
        r == 0 || throw("Number of rows plus padding $stride_AD not a multiple of register size: $REGISTER_SIZE.")
        L = CACHELINE_SIZE
    else
        W = r
        Q = 1
    end
    V = Vec{W,T}
    C = CACHELINE_SIZE ÷ T_size
    common = quote
        vC1 = vbroadcast($V, c1)
        vC2 = vbroadcast($V, -c2)
        ptr_invH, ptr_S, ptr_U = pointer(invH), pointer(s), pointer(u)
    end
    if Q > 1
        return quote
            $common
            # @nexprs $Pₖ p -> @nexprs $Q q -> invH_p_q = vload($V, ptr_invH + $REGISTER_SIZE*(q-1) + $AD_stride*(p-1))

            # invH = invH + c1 * (s * s') - c2 * (u * s' + s * u')
            # @nexprs $Pₖ p -> begin
            for p ∈ 0:$T_size:$((Pₖ-1)*T_size)
                # @nexprs $Q q -> invH_q = vload($V, ptr_invH + $REGISTER_SIZE*(q-1) + $AD_stride*(p-1))
                # @nexprs $Q q -> invH_q = vload($V, ptr_invH + $REGISTER_SIZE*(q-1) + $AD_stride*p)
                # vSb = vbroadcast($V, unsafe_load(ptr_S + p-1 ))
                vSb = vbroadcast($V, unsafe_load(ptr_S + p ))
                vSbc1 = evmul(vSb, vC1)
                vSbc2 = evmul(vSb, vC2)
                # vUbc2 = vbroadcast($V, unsafe_load(ptr_U + p-1 )) * vC2
                vUbc2 = evmul(vbroadcast($V, unsafe_load(ptr_U + p )), vC2)
                # or
                # vSbc1 = vbroadcast($V, c1*unsafe_load(ptr_S + p-1 ))
                # vSbc2 = vbroadcast($V, c2*unsafe_load(ptr_S + p-1 ))
                # vUbc2 = vbroadcast($V, c2*unsafe_load(ptr_U + p-1 ))
                @nexprs $Q q -> begin # I am concerned over the size of these dependency chains.
                    invH_q = vload($V, ptr_invH + $REGISTER_SIZE*(q-1) + $stride_AD*p)
                    vU_q = vload($V, ptr_U + $REGISTER_SIZE*(q-1))
                    invH_q = vmuladd(vU_q, vSbc2, invH_q)
                    vS_q = vload($V, ptr_S + $REGISTER_SIZE*(q-1))
                    invH_q = vmuladd(vS_q, vSbc1, vmuladd(vS_q, vUbc2, invH_q))
                    vstore!(ptr_invH + $REGISTER_SIZE*(q-1) + $stride_AD*p, invH_q)
                end
            end
            nothing
        end
    else
        return quote
            $common
            # invH = invH + c1 * (s * s') - c2 * (u * s' + s * u')
            @nexprs $Pₖ p -> begin
                invH_p = vload($V, ptr_invH + $AD_stride*(p-1))
                vSb = vbroadcast($V, unsafe_load(ptr_S + (p-1)*$T_size ))
                vS = vload($V, ptr_S)
                # Split up the dependency chain and reduce number of operations, when we can't save on vC1 and vC2 multiplications.
                invH_p = vmuladd(vC2, vmuladd( vload($V, ptr_U), vSb, evmul(vS, vbroadcast($V, unsafe_load(ptr_U + (p-1)*$T_size )))), vmuladd( vS, evmul(vSb,vC1), invH_p ))
                vstore!(ptr_invH + $AD_stride*(p-1), invH_p)
            end
            nothing
        end
    end
end

@generated function BFGS_update!(invH::Union{Symmetric{T,SizedSIMDMatrix{P,P,T,R,L}},SizedSIMDMatrix{P,P,T,R,L}},
    s::SizedSIMDVector{P,T,R}, u::SizedSIMDVector{P,T,R}, c1::T, c2::T) where {P,T,R,L}

    BFGS_update_quote(P,P,R,T)

end
